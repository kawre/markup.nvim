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
    /// Cells holding text, from start to end. Borders and padding are left out.
    pub spans: Vec<(i32, i32)>,
}

/// A run of text on a row. Text is borrowed from the tree until it has to be
/// cut by something painted over it.
#[derive(Clone)]
struct Segment<'a> {
    cell: i32,
    width: i32,
    text: Cow<'a, str>,
    /// Width of each non ASCII character, as measured by Neovim.
    cells: Cow<'a, [u8]>,
}

impl<'a> Segment<'a> {
    fn end(&self) -> i32 {
        self.cell + self.width
    }

    /// Every character with its byte offset, starting cell and width.
    fn characters(&self) -> impl Iterator<Item = (usize, char, i32, i32)> + '_ {
        let mut cells = self.cells.iter().copied();
        let mut cell = self.cell;
        self.text.char_indices().map(move |(byte, character)| {
            let width = if character.is_ascii() {
                1
            } else {
                cells.next().map_or(1, i32::from)
            };
            let start = cell;
            cell += width;
            (byte, character, start, width)
        })
    }

    /// The part between two cells. A wide character on the edge cannot be
    /// halved, so the half that remains becomes a blank.
    fn slice(&self, from: i32, to: i32) -> Segment<'a> {
        let mut text = String::new();
        let mut cells = Vec::new();

        for (_, character, cell, width) in self.characters() {
            let overlap = cell.max(from)..(cell + width).min(to);
            if overlap.is_empty() {
                continue;
            }

            if overlap.len() as i32 == width {
                text.push(character);
                if !character.is_ascii() {
                    cells.push(width as u8);
                }
            } else {
                text.extend(std::iter::repeat_n(' ', overlap.len()));
            }
        }

        Segment {
            cell: from,
            width: to - from,
            text: Cow::Owned(text),
            cells: Cow::Owned(cells),
        }
    }

    /// Byte offset of a cell inside this segment, snapped to a character.
    fn byte_at(&self, target: i32) -> usize {
        self.characters()
            .find(|&(_, _, cell, width)| cell + width > target)
            .map_or(self.text.len(), |(byte, ..)| byte)
    }
}

/// One row while it is painted, in cells. Segments stay sorted and never
/// overlap, which is what lets later paint cover earlier paint.
#[derive(Default)]
struct Row<'a> {
    segments: Vec<Segment<'a>>,
    ranges: Vec<(i32, i32, u32)>,
    spans: Vec<(i32, i32)>,
}

impl<'a> Row<'a> {
    /// Writes the text of a node, as opposed to what decorates it.
    fn write_text(&mut self, cell: i32, text: Cow<'a, str>, width: i32, cells: Cow<'a, [u8]>) {
        let leading = text.len() - text.trim_start_matches(' ').len();
        let trailing = text.len() - text.trim_end_matches(' ').len();
        if leading < text.len() {
            self.spans.push((cell + leading as i32, cell + width - trailing as i32));
        }

        self.write(cell, text, width, cells);
    }

    fn write(&mut self, cell: i32, text: Cow<'a, str>, width: i32, cells: Cow<'a, [u8]>) {
        let segment = Segment { cell, width, text, cells };

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

            start + segment.byte_at(cell)
        };

        let marks = self
            .ranges
            .iter()
            .filter(|range| range.1 > range.0)
            .filter(|range| range.1 > 0)
            .map(|&(start, end, hl)| Mark {
                // Something placed before the first column must not wrap around.
                start: byte_at(start.max(0)) as u32,
                end: byte_at(end) as u32,
                hl,
            })
            .collect();

        Line { text, marks, spans: self.spans }
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
    /// Rows a clipping ancestor leaves visible.
    visible: std::ops::Range<i32>,
    /// Where containing blocks ended up, only tracked when something needs it.
    origins: HashMap<Index, (i32, i32)>,
}

impl<'a> Painter<'a> {
    fn row(&mut self, row: i32) -> Option<&mut Row<'a>> {
        if self.visible.contains(&row) {
            self.rows.get_mut(row as usize)
        } else {
            None
        }
    }

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
                    let all = node.cells.as_deref().unwrap_or(&[]);
                    for fragment in fragments {
                        if let Some(row) = self.row(y + fragment.y) {
                            let (start, end) = (fragment.start as usize, fragment.end as usize);
                            let wide = |text: &str| text.chars().filter(|c| !c.is_ascii()).count();

                            // Measured widths only cover this fragment's characters.
                            let first = wide(&node.text[..start]).min(all.len());
                            let last = (first + wide(&node.text[start..end])).min(all.len());

                            let text = Cow::Borrowed(&node.text[start..end]);
                            row.write_text(x + fragment.x, text, fragment.width, Cow::Borrowed(&all[first..last]));
                        }
                    }
                }
                None => {
                    if let Some(row) = self.row(y) {
                        let cells = node.cells.as_deref().unwrap_or(&[]);
                        row.write_text(x, Cow::Borrowed(&node.text), node.text_width, Cow::Borrowed(cells));
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
                if let Some(row) = self.row(y + fragment.y) {
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
                if let Some(row) = self.row(row) {
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

        let outer_visible = self.visible.clone();
        if style.extra().clip {
            let bottom = y + margin.top + padding.vertical() + geometry.content.height;
            self.visible = self.visible.start.max(y)..self.visible.end.min(bottom);
        }

        let content_x = x + margin.left + padding.left;
        let content_y = y + margin.top + padding.top;
        for &child in &node.children {
            self.visit(child, content_x, content_y);
        }

        self.visible = outer_visible;

        // Painted last, so rows stay in order and take the fast path.
        if let Some(frame) = &frame {
            self.paint_frame_end(frame);
        }
    }

    fn put(&mut self, row: i32, cell: i32, text: String, width: i32, hl: u32) {
        if let Some(line) = self.row(row) {
            line.write(cell, Cow::Owned(text), width, Cow::Borrowed(&[]));
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
        visible: 0..height.max(0),
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
        let base = wide_text(&mut tree, 1, "你好", &[2, 2], 4);
        let root = tree.create(2, Display::Block).unwrap();
        tree.insert(root, base, None).unwrap();
        let top = overlay(&mut tree, 3, "X", 1, 0);
        tree.insert(root, top, None).unwrap();

        assert_eq!(render_with_absolutes(&mut tree, root)[0].text, " X好");
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

    fn wide_text(tree: &mut Tree, id: u32, value: &str, cells: &[u8], width: i32) -> Index {
        let index = text(tree, id, value, width);
        tree.node_mut(index).cells = Some(cells.to_vec().into_boxed_slice());
        index
    }

    #[test]
    fn overlays_keep_mixed_width_text_around_them() {
        let mut tree = Tree::default();
        let base = wide_text(&mut tree, 1, "ab你好cd", &[2, 2], 8);
        let root = tree.create(2, Display::Block).unwrap();
        tree.insert(root, base, None).unwrap();
        let top = overlay(&mut tree, 3, "X", 6, 0);
        tree.insert(root, top, None).unwrap();

        assert_eq!(render_with_absolutes(&mut tree, root)[0].text, "ab你好Xd");
    }

    #[test]
    fn half_of_a_wide_character_becomes_a_blank() {
        let mut tree = Tree::default();
        let base = wide_text(&mut tree, 1, "你好世界", &[2, 2, 2, 2], 8);
        let root = tree.create(2, Display::Block).unwrap();
        tree.insert(root, base, None).unwrap();
        let top = overlay(&mut tree, 3, "X", 3, 0);
        tree.insert(root, top, None).unwrap();

        assert_eq!(render_with_absolutes(&mut tree, root)[0].text, "你 X世界");
    }

    #[test]
    fn highlights_inside_wide_text_use_real_widths() {
        let mut row = Row::default();
        row.write(0, Cow::Borrowed("a你b"), 4, Cow::Borrowed(&[2]));
        row.ranges.push((1, 3, 7));

        assert_eq!(row.finish().marks, vec![Mark { start: 1, end: 4, hl: 7 }]);
    }

    #[test]
    fn marks_before_the_first_column_do_not_wrap_around() {
        let row = Row {
            segments: Vec::new(),
            ranges: vec![(-9, 4, 1), (-5, -2, 2)],
            spans: Vec::new(),
        };

        let line = row.finish();

        assert_eq!(line.marks.len(), 1);
        assert_eq!((line.marks[0].start, line.marks[0].end), (0, 4));
    }

    #[test]
    fn spans_cover_text_without_its_blanks() {
        let mut row = Row::default();
        row.write_text(2, Cow::Borrowed("  ab "), 5, Cow::Borrowed(&[]));
        row.write_text(9, Cow::Borrowed("   "), 3, Cow::Borrowed(&[]));
        row.write(14, Cow::Borrowed("edge"), 4, Cow::Borrowed(&[]));

        assert_eq!(row.finish().spans, vec![(4, 6)]);
    }

    #[test]
    fn clipping_hides_rows_past_the_height() {
        let mut tree = Tree::default();
        let first = text(&mut tree, 1, "aa", 2);
        let a = tree.create(2, Display::Block).unwrap();
        tree.insert(a, first, None).unwrap();
        let second = text(&mut tree, 3, "bb", 2);
        let b = tree.create(4, Display::Block).unwrap();
        tree.insert(b, second, None).unwrap();

        let clipped = tree.create(5, Display::Block).unwrap();
        tree.insert(clipped, a, None).unwrap();
        tree.insert(clipped, b, None).unwrap();
        let style = &mut tree.node_mut(clipped).style;
        style.height = crate::engine::style::Length::Cells(1);
        style.extra_mut().clip = true;

        let after = text(&mut tree, 6, "cc", 2);
        let root = tree.create(7, Display::Block).unwrap();
        tree.insert(root, clipped, None).unwrap();
        tree.insert(root, after, None).unwrap();

        assert_eq!(texts(&render(&mut tree, root)), vec!["aa", "cc"]);
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
