//! Turns a laid out tree into lines of text with highlight ranges.

use super::style::{Border, Display, Position};
use super::tree::{Index, Tree};
use std::borrow::Cow;
use std::collections::HashMap;

/// A highlight range in bytes, within one line.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Mark {
    pub start: u32,
    pub end: u32,
    pub hl: u32,
}

#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct Line {
    pub text: String,
    pub marks: Vec<Mark>,
}

/// A run of text on a row. Text is borrowed from the tree until it has to be
/// cut by something painted over it.
#[derive(Clone)]
struct Segment<'a> {
    cell: i32,
    width: i32,
    text: Cow<'a, str>,
}

impl<'a> Segment<'a> {
    fn end(&self) -> i32 {
        self.cell + self.width
    }

    /// The part between two cells. Neovim measured the whole text, so a cut
    /// through text of mixed widths has to fall back to blanks.
    fn slice(&self, from: i32, to: i32) -> Segment<'a> {
        let (start, stop) = ((from - self.cell) as usize, (to - self.cell) as usize);
        let width = to - from;

        let text = if self.text.len() == self.width as usize {
            self.text[start..stop].to_string()
        } else if self.text.chars().count() == self.width as usize {
            self.text.chars().skip(start).take(stop - start).collect()
        } else {
            " ".repeat(width as usize)
        };

        Segment {
            cell: from,
            width,
            text: Cow::Owned(text),
        }
    }
}

/// One row while it is painted, in cells. Segments stay sorted and never
/// overlap, which is what lets later paint cover earlier paint.
#[derive(Default)]
struct Row<'a> {
    segments: Vec<Segment<'a>>,
    ranges: Vec<(i32, i32, u32)>,
}

impl<'a> Row<'a> {
    fn write(&mut self, cell: i32, text: Cow<'a, str>, width: i32) {
        let segment = Segment { cell, width, text };

        // Normal flow runs left to right and always takes this path.
        if self.segments.last().is_none_or(|last| last.end() <= cell) {
            self.segments.push(segment);
            return;
        }

        self.cut_text(cell, cell + width);
        let position = self.segments.partition_point(|other| other.cell < cell);
        self.segments.insert(position, segment);
    }

    fn cut_text(&mut self, from: i32, to: i32) {
        let mut kept = Vec::with_capacity(self.segments.len() + 1);
        for segment in self.segments.drain(..) {
            if segment.end() <= from || segment.cell >= to {
                kept.push(segment);
                continue;
            }
            if segment.cell < from {
                kept.push(segment.slice(segment.cell, from));
            }
            if segment.end() > to {
                kept.push(segment.slice(to, segment.end()));
            }
        }
        self.segments = kept;
    }

    /// Removes everything under a box, so an overlay hides what it covers.
    fn cover(&mut self, from: i32, to: i32) {
        self.cut_text(from, to);

        let mut kept = Vec::with_capacity(self.ranges.len() + 1);
        for &(start, end, hl) in &self.ranges {
            if end <= from || start >= to {
                kept.push((start, end, hl));
                continue;
            }
            if start < from {
                kept.push((start, from, hl));
            }
            if end > to {
                kept.push((to, end, hl));
            }
        }
        self.ranges = kept;
    }

    fn finish(self) -> Line {
        let right = self.ranges.iter().map(|range| range.1).max().unwrap_or(0);

        let capacity = self.segments.iter().map(|segment| segment.text.len()).sum::<usize>();
        let mut text = String::with_capacity(capacity + 8);
        let mut cells = 0;
        // Where each segment landed, to turn cells into bytes.
        let mut starts = Vec::with_capacity(self.segments.len());
        // When every cell is one byte, nothing needs looking up.
        let mut plain = true;

        for segment in &self.segments {
            text.extend(std::iter::repeat_n(' ', (segment.cell - cells).max(0) as usize));
            starts.push(text.len());
            text.push_str(&segment.text);
            cells = segment.end();
            plain &= segment.text.len() == segment.width as usize;
        }
        text.extend(std::iter::repeat_n(' ', (right - cells).max(0) as usize));

        let byte_at = |cell: i32| -> usize {
            if plain {
                return cell as usize;
            }

            let index = self.segments.partition_point(|segment| segment.cell <= cell);
            let Some(index) = index.checked_sub(1) else {
                return cell as usize;
            };

            let segment = &self.segments[index];
            let start = starts[index];
            if cell >= segment.end() {
                return start + segment.text.len() + (cell - segment.end()) as usize;
            }

            let share = (cell - segment.cell) as usize * segment.text.len();
            let mut byte = start + share / segment.width.max(1) as usize;
            while !text.is_char_boundary(byte) {
                byte += 1;
            }
            byte
        };

        let marks = self
            .ranges
            .iter()
            .filter(|range| range.1 > range.0)
            .map(|&(start, end, hl)| Mark {
                start: byte_at(start) as u32,
                end: byte_at(end) as u32,
                hl,
            })
            .collect();

        Line { text, marks }
    }
}

/// A border and the box it goes around.
struct Frame<'a> {
    border: &'a Border,
    left: i32,
    top: i32,
    width: i32,
    height: i32,
}

impl Frame<'_> {
    /// A full row, with corners only where a side meets it.
    fn horizontal(&self, start: char, middle: char, end: char) -> String {
        let width = self.width.max(0) as usize;
        let mut text = String::with_capacity(width * 3);
        for cell in 0..width {
            text.push(match cell {
                0 if self.border.left => start,
                cell if cell + 1 == width && self.border.right => end,
                _ => middle,
            });
        }
        text
    }

    /// Rows between the top and bottom borders.
    fn side_rows(&self) -> std::ops::Range<i32> {
        let top = self.top + self.border.top as i32;
        let bottom = self.top + self.height - self.border.bottom as i32;
        top..bottom
    }
}

struct Painter<'a> {
    tree: &'a Tree,
    rows: Vec<Row<'a>>,
    /// Absolute nodes found so far, painted after everything in flow.
    pending: Vec<Index>,
    /// Where containing blocks ended up, only tracked when something needs it.
    origins: HashMap<Index, (i32, i32)>,
}

impl Painter<'_> {
    fn visit(&mut self, index: Index, x: i32, y: i32) {
        let tree = self.tree;
        let node = tree.node(index);

        if node.display == Display::Contents {
            for &child in &node.children {
                self.visit(child, x, y);
            }
            return;
        }

        if node.style.position() == Position::Absolute {
            self.pending.push(index);
            return;
        }

        let (shift_x, shift_y) = node.style.relative_offset();
        self.paint_box(index, x + node.geometry.x + shift_x, y + node.geometry.y + shift_y);
    }

    /// Paints a node whose margin box starts at `x`, `y`.
    fn paint_box(&mut self, index: Index, x: i32, y: i32) {
        let tree = self.tree;
        let node = tree.node(index);

        if node.display == Display::Text {
            match &node.fragments {
                Some(fragments) => {
                    for fragment in fragments {
                        if let Some(row) = self.rows.get_mut((y + fragment.y) as usize) {
                            let text = &node.text[fragment.start as usize..fragment.end as usize];
                            row.write(x + fragment.x, Cow::Borrowed(text), fragment.width);
                        }
                    }
                }
                None => {
                    if let Some(row) = self.rows.get_mut(y as usize) {
                        row.write(x, Cow::Borrowed(&node.text), node.text_width);
                    }
                }
            }
            return;
        }

        let track = !tree.absolutes().is_empty();
        if track && (node.parent.is_none() || node.style.position() != Position::Static) {
            self.origins.insert(index, (x, y));
        }

        let style = &node.style;
        let (margin, padding) = (style.margin, style.inner());
        let geometry = &node.geometry;

        if let (true, Some(fragments)) = (style.hl != 0, &node.fragments) {
            for fragment in fragments {
                if let Some(row) = self.rows.get_mut((y + fragment.y) as usize) {
                    let left = x + fragment.x;
                    row.ranges.push((left, left + fragment.width, style.hl));
                }
            }
        } else if style.hl != 0 {
            let left = x + margin.left;
            let right = left + padding.horizontal() + geometry.content.width;
            let mut top = y + margin.top;
            let mut bottom = top + padding.vertical() + geometry.content.height;
            if style.border().is_some_and(|border| border.outside_background) {
                let edges = style.border_edges();
                top += edges.top;
                bottom -= edges.bottom;
            }
            for row in top..bottom {
                if let Some(row) = self.rows.get_mut(row as usize) {
                    row.ranges.push((left, right, style.hl));
                }
            }
        }

        let frame = style.border().map(|border| Frame {
            border,
            left: x + margin.left,
            top: y + margin.top,
            width: padding.horizontal() + geometry.content.width,
            height: padding.vertical() + geometry.content.height,
        });

        if let Some(frame) = &frame {
            self.paint_frame_start(frame);
        }

        let content_x = x + margin.left + padding.left;
        let content_y = y + margin.top + padding.top;
        for &child in &node.children {
            self.visit(child, content_x, content_y);
        }

        // Painted last, so rows stay in order and take the fast path.
        if let Some(frame) = &frame {
            self.paint_frame_end(frame);
        }
    }

    fn put(&mut self, row: i32, cell: i32, text: String, width: i32, hl: u32) {
        if let Some(line) = self.rows.get_mut(row as usize) {
            line.write(cell, Cow::Owned(text), width);
            if hl != 0 {
                line.ranges.push((cell, cell + width, hl));
            }
        }
    }

    /// The top row and the left column.
    fn paint_frame_start(&mut self, frame: &Frame) {
        let border = frame.border;

        if border.top {
            let text = frame.horizontal(border.chars[0], border.chars[1], border.chars[2]);
            self.put(frame.top, frame.left, text, frame.width, border.hl);
        }

        if border.left {
            for row in frame.side_rows() {
                self.put(row, frame.left, border.chars[7].to_string(), 1, border.hl);
            }
        }
    }

    /// The right column and the bottom row.
    fn paint_frame_end(&mut self, frame: &Frame) {
        let border = frame.border;

        if border.right {
            let cell = frame.left + frame.width - 1;
            for row in frame.side_rows() {
                self.put(row, cell, border.chars[3].to_string(), 1, border.hl);
            }
        }

        if border.bottom {
            let text = frame.horizontal(border.chars[6], border.chars[5], border.chars[4]);
            let row = frame.top + frame.height - 1;
            self.put(row, frame.left, text, frame.width, border.hl);
        }
    }

    /// Paints absolute nodes from the lowest `z` up. Each one hides what it
    /// covers, and may reveal more absolute nodes inside it.
    fn paint_absolutes(&mut self) {
        while !self.pending.is_empty() {
            let tree = self.tree;
            let next = (0..self.pending.len())
                .min_by_key(|&position| tree.node(self.pending[position]).style.extra().z)
                .unwrap_or(0);
            let index = self.pending.remove(next);

            let block = tree.containing_block(index);
            let (block_x, block_y) = self.origins.get(&block).copied().unwrap_or((0, 0));
            let margin = tree.node(block).style.margin;

            let geometry = &tree.node(index).geometry;
            let x = block_x + margin.left + geometry.x;
            let y = block_y + margin.top + geometry.y;

            for row in y..y + geometry.outer.height {
                if let Some(row) = self.rows.get_mut(row as usize) {
                    row.cover(x, x + geometry.outer.width);
                }
            }

            self.paint_box(index, x, y);
        }
    }
}

/// Paints the subtree under `root` into `height` lines.
pub fn paint(tree: &Tree, root: Index, height: i32) -> Vec<Line> {
    let mut painter = Painter {
        tree,
        rows: (0..height.max(0)).map(|_| Row::default()).collect(),
        pending: Vec::new(),
        origins: HashMap::new(),
    };

    painter.paint_box(root, 0, 0);
    painter.paint_absolutes();
    painter.rows.into_iter().map(Row::finish).collect()
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::engine::layout::{Constraints, measure};
    use crate::engine::tree::Tree;

    fn text(tree: &mut Tree, id: u32, value: &str, width: i32) -> Index {
        let index = tree.create(id, Display::Text).unwrap();
        let node = tree.node_mut(index);
        node.text = value.to_string();
        node.text_width = width;
        index
    }

    fn inline(tree: &mut Tree, id: u32, child: Index, hl: u32) -> Index {
        let index = tree.create(id, Display::Inline).unwrap();
        tree.insert(index, child, None).unwrap();
        tree.node_mut(index).style.hl = hl;
        index
    }

    fn render(tree: &mut Tree, root: Index) -> Vec<Line> {
        let height = measure(tree, root, Constraints::available(20)).height;
        paint(tree, root, height)
    }

    #[test]
    fn writes_text_and_marks_in_bytes() {
        let mut tree = Tree::default();
        let a = text(&mut tree, 1, "ab", 2);
        let a = inline(&mut tree, 2, a, 7);
        let b = text(&mut tree, 3, "cd", 2);
        let b = inline(&mut tree, 4, b, 8);
        let root = tree.create(5, Display::Block).unwrap();
        tree.insert(root, a, None).unwrap();
        tree.insert(root, b, None).unwrap();

        let lines = render(&mut tree, root);

        assert_eq!(lines[0].text, "abcd");
        assert_eq!(lines[0].marks, vec![
            Mark { start: 0, end: 2, hl: 7 },
            Mark { start: 2, end: 4, hl: 8 },
        ]);
    }

    #[test]
    fn marks_after_multibyte_text_use_byte_offsets() {
        let mut tree = Tree::default();
        let wide = text(&mut tree, 1, "你", 2);
        let wide = inline(&mut tree, 2, wide, 7);
        let ascii = text(&mut tree, 3, "ab", 2);
        let ascii = inline(&mut tree, 4, ascii, 8);
        let root = tree.create(5, Display::Block).unwrap();
        tree.insert(root, wide, None).unwrap();
        tree.insert(root, ascii, None).unwrap();

        let lines = render(&mut tree, root);

        assert_eq!(lines[0].marks, vec![
            Mark { start: 0, end: 3, hl: 7 },
            Mark { start: 3, end: 5, hl: 8 },
        ]);
    }

    fn overlay(tree: &mut Tree, id: u32, value: &str, left: i32, hl: u32) -> Index {
        let label = text(tree, id + 100, value, value.len() as i32);
        let index = inline(tree, id, label, hl);
        let extra = tree.node_mut(index).style.extra_mut();
        extra.position = Position::Absolute;
        extra.inset.left = Some(left);
        extra.inset.top = Some(0);
        tree.sync_position(index);
        index
    }

    fn render_with_absolutes(tree: &mut Tree, root: Index) -> Vec<Line> {
        let height = measure(tree, root, Constraints::available(20)).height;
        crate::engine::layout::absolute::layout(tree);
        paint(tree, root, height)
    }

    #[test]
    fn absolute_boxes_replace_the_text_under_them() {
        let mut tree = Tree::default();
        let base = text(&mut tree, 1, "abcdefgh", 8);
        let root = tree.create(2, Display::Block).unwrap();
        tree.insert(root, base, None).unwrap();
        let top = overlay(&mut tree, 3, "XY", 2, 0);
        tree.insert(root, top, None).unwrap();

        assert_eq!(render_with_absolutes(&mut tree, root)[0].text, "abXYefgh");
    }

    #[test]
    fn absolute_boxes_cut_highlights_under_them() {
        let mut tree = Tree::default();
        let label = text(&mut tree, 1, "abcdefgh", 8);
        let base = inline(&mut tree, 2, label, 7);
        let root = tree.create(3, Display::Block).unwrap();
        tree.insert(root, base, None).unwrap();
        let top = overlay(&mut tree, 4, "XY", 2, 8);
        tree.insert(root, top, None).unwrap();

        let marks = render_with_absolutes(&mut tree, root).remove(0).marks;

        assert_eq!(marks, vec![
            Mark { start: 0, end: 2, hl: 7 },
            Mark { start: 4, end: 8, hl: 7 },
            Mark { start: 2, end: 4, hl: 8 },
        ]);
    }

    #[test]
    fn higher_z_paints_last() {
        let mut tree = Tree::default();
        let root = tree.create(1, Display::Block).unwrap();
        let low = overlay(&mut tree, 2, "AAAA", 0, 0);
        let high = overlay(&mut tree, 3, "BB", 1, 0);
        tree.node_mut(low).style.extra_mut().z = 1;
        tree.node_mut(high).style.extra_mut().z = 2;
        tree.insert(root, high, None).unwrap();
        tree.insert(root, low, None).unwrap();
        let base = text(&mut tree, 4, "_", 1);
        tree.insert(root, base, None).unwrap();

        assert_eq!(render_with_absolutes(&mut tree, root)[0].text, "ABBA");
    }

    #[test]
    fn cutting_wide_text_leaves_blanks_not_broken_characters() {
        let mut tree = Tree::default();
        let base = text(&mut tree, 1, "你好", 4);
        let root = tree.create(2, Display::Block).unwrap();
        tree.insert(root, base, None).unwrap();
        let top = overlay(&mut tree, 3, "X", 1, 0);
        tree.insert(root, top, None).unwrap();

        assert_eq!(render_with_absolutes(&mut tree, root)[0].text, " X  ");
    }

    fn framed(tree: &mut Tree, sides: [bool; 4], outside_background: bool) -> Index {
        let label = text(tree, 1, "ab", 2);
        let root = tree.create(2, Display::Block).unwrap();
        tree.insert(root, label, None).unwrap();

        let style = &mut tree.node_mut(root).style;
        style.width = crate::engine::style::Length::Cells(4);
        style.hl = 7;
        style.extra_mut().border = Some(Border {
            chars: ['╭', '─', '╮', '│', '╯', '─', '╰', '│'],
            top: sides[0],
            right: sides[1],
            bottom: sides[2],
            left: sides[3],
            hl: 9,
            outside_background,
        });
        root
    }

    fn texts(lines: &[Line]) -> Vec<&str> {
        lines.iter().map(|line| line.text.as_str()).collect()
    }

    #[test]
    fn draws_a_full_border() {
        let mut tree = Tree::default();
        let root = framed(&mut tree, [true; 4], false);

        let lines = render(&mut tree, root);

        assert_eq!(texts(&lines), vec!["╭────╮", "│ab  │", "╰────╯"]);
    }

    #[test]
    fn draws_only_the_sides_asked_for() {
        let mut tree = Tree::default();
        let root = framed(&mut tree, [true, false, true, false], false);

        let lines = render(&mut tree, root);

        assert_eq!(texts(&lines), vec!["────", "ab  ", "────"]);
    }

    #[test]
    fn the_border_takes_space_in_layout() {
        let mut tree = Tree::default();
        let root = framed(&mut tree, [true; 4], false);
        tree.node_mut(root).style.margin.left = 1;

        let size = measure(&mut tree, root, Constraints::available(20));

        assert_eq!((size.width, size.height), (7, 3));
    }

    #[test]
    fn the_background_covers_the_border_by_default() {
        let mut tree = Tree::default();
        let root = framed(&mut tree, [true; 4], false);

        let lines = render(&mut tree, root);

        assert!(lines[0].marks.iter().any(|mark| mark.hl == 7));
    }

    #[test]
    fn half_borders_keep_the_background_off_their_rows() {
        let mut tree = Tree::default();
        let root = framed(&mut tree, [true, false, true, false], true);

        let lines = render(&mut tree, root);

        assert!(lines[0].marks.iter().all(|mark| mark.hl == 9));
        assert!(lines[1].marks.iter().any(|mark| mark.hl == 7));
        assert!(lines[2].marks.iter().all(|mark| mark.hl == 9));
    }

    #[test]
    fn highlights_extend_over_padding() {
        let mut tree = Tree::default();
        let label = text(&mut tree, 1, "ab", 2);
        let padded = inline(&mut tree, 2, label, 7);
        tree.node_mut(padded).style.padding.right = 3;
        let root = tree.create(3, Display::Block).unwrap();
        tree.insert(root, padded, None).unwrap();

        let lines = render(&mut tree, root);

        assert_eq!(lines[0].text, "ab   ");
        assert_eq!(lines[0].marks[0].end, 5);
    }
}
