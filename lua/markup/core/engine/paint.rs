//! Turns a laid out tree into lines of text with highlight ranges.

use super::style::Display;
use super::tree::{Index, Tree};

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

/// A piece of text on a line, used to map cells to bytes.
#[derive(Clone, Copy)]
struct Span {
    cell: i32,
    byte: usize,
    width: i32,
    bytes: usize,
}

#[derive(Default)]
struct Row {
    text: String,
    cells: i32,
    ascii: bool,
    spans: Vec<Span>,
    ranges: Vec<(i32, i32, u32)>,
}

impl Row {
    fn pad_to(&mut self, cell: i32) {
        if cell > self.cells {
            let gap = (cell - self.cells) as usize;
            self.text.extend(std::iter::repeat_n(' ', gap));
            self.cells = cell;
        }
    }

    fn write(&mut self, cell: i32, text: &str, width: i32) {
        self.pad_to(cell);
        if !text.is_ascii() || width != text.len() as i32 {
            self.ascii = false;
            self.spans.push(Span {
                cell: self.cells,
                byte: self.text.len(),
                width,
                bytes: text.len(),
            });
        }
        self.text.push_str(text);
        self.cells += width;
    }

    /// Byte offset of a cell, snapped to a character boundary.
    fn byte_at(&self, cell: i32) -> usize {
        if self.ascii {
            return cell as usize;
        }

        // Spans list the non ASCII text, the rest of the row is one byte per cell.
        let mut extra = 0;
        for span in &self.spans {
            if cell < span.cell {
                break;
            }
            if cell < span.cell + span.width {
                let share = (cell - span.cell) as usize * span.bytes / span.width.max(1) as usize;
                let mut byte = span.byte + share;
                while !self.text.is_char_boundary(byte) {
                    byte += 1;
                }
                return byte;
            }
            extra = span.byte + span.bytes - (span.cell + span.width) as usize;
        }
        cell as usize + extra
    }

    fn finish(mut self) -> Line {
        let right = self.ranges.iter().map(|range| range.1).max().unwrap_or(0);
        self.pad_to(right);

        let marks = self
            .ranges
            .iter()
            .filter(|range| range.1 > range.0)
            .map(|&(start, end, hl)| Mark {
                start: self.byte_at(start) as u32,
                end: self.byte_at(end) as u32,
                hl,
            })
            .collect();

        Line {
            text: self.text,
            marks,
        }
    }
}

/// Paints the subtree under `root` into `height` lines.
pub fn paint(tree: &Tree, root: Index, height: i32) -> Vec<Line> {
    let mut rows: Vec<Row> = (0..height.max(0))
        .map(|_| Row {
            ascii: true,
            ..Row::default()
        })
        .collect();

    visit(tree, root, 0, 0, &mut rows);
    rows.into_iter().map(Row::finish).collect()
}

fn visit(tree: &Tree, index: Index, x: i32, y: i32, rows: &mut [Row]) {
    let node = tree.node(index);

    if node.display == Display::Contents {
        for &child in &node.children {
            visit(tree, child, x, y, rows);
        }
        return;
    }

    let geometry = &node.geometry;
    let (x, y) = (x + geometry.x, y + geometry.y);

    if node.display == Display::Text {
        if let Some(row) = rows.get_mut(y as usize) {
            row.write(x, &node.text, node.text_width);
        }
        return;
    }

    let style = &node.style;
    let (margin, padding) = (style.margin, style.padding);

    if style.hl != 0 {
        let left = x + margin.left;
        let right = left + padding.horizontal() + geometry.content.width;
        let top = y + margin.top;
        let bottom = top + padding.vertical() + geometry.content.height;
        for row in top..bottom {
            if let Some(row) = rows.get_mut(row as usize) {
                row.ranges.push((left, right, style.hl));
            }
        }
    }

    let content_x = x + margin.left + padding.left;
    let content_y = y + margin.top + padding.top;
    for &child in &node.children {
        visit(tree, child, content_x, content_y, rows);
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::engine::layout::measure;
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
        let height = measure(tree, root, 20).height;
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
