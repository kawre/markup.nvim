use super::{Space, Strategy, measure, place, wrap};
use crate::engine::tree::{Index, Size, Tree};

/// Stacks block children. Runs of inline children share a line, and wrap when
/// they do not fit.
pub struct Block;

/// Places a finished run of inline children.
fn flush_run(
    tree: &mut Tree,
    run: &mut Vec<Index>,
    cursor: &mut Cursor,
    space: Space,
    wraps: bool,
) {
    if run.is_empty() {
        return;
    }

    // Laying the run out plainly is cheap, and it is all that most UIs need.
    let top = cursor.y();
    let mut x = 0;
    let mut height = 0;
    for &child in run.iter() {
        let outer = measure(tree, child, space.child((space.width - x).max(0)));
        place(tree, child, x, top);
        x += outer.width;
        height = height.max(outer.height);
    }

    let overflows = wraps && space.can_wrap() && x > space.width;

    if overflows || height > 1 {
        let limit = if overflows { space.width } else { i32::MAX };
        let size = wrap::flow(tree, run, limit, space.width);
        for &child in run.iter() {
            place(tree, child, 0, top);
        }
        cursor.extend_line(size);
    } else {
        cursor.extend_line(Size { width: x, height });
    }

    cursor.end_line();
    run.clear();
}

impl Strategy for Block {
    fn arrange(&self, tree: &mut Tree, node: Index, space: Space) -> Size {
        let style = &tree.node(node).style;
        let (reverse, spacing) = (style.reverse, style.spacing);
        let wraps = tree.text_wraps(node);

        let mut cursor = Cursor {
            spacing,
            ..Cursor::default()
        };
        let mut run = Vec::new();

        tree.for_each_flow_child(node, reverse, &mut |tree, child| {
            if tree.node(child).display.is_inline() {
                run.push(child);
            } else {
                flush_run(tree, &mut run, &mut cursor, space, wraps);
                let outer = measure(tree, child, space.child(space.width));
                place(tree, child, 0, cursor.y());
                cursor.extend_line(outer);
                cursor.end_line();
            }
        });

        flush_run(tree, &mut run, &mut cursor, space, wraps);

        Size {
            width: cursor.width,
            height: cursor.height,
        }
    }
}

/// Tracks the current line while children are placed.
#[derive(Default)]
struct Cursor {
    spacing: i32,
    x: i32,
    line_height: i32,
    line_open: bool,
    width: i32,
    height: i32,
    rows: i32,
}

impl Cursor {
    /// Top of the current line, leaving room for spacing after earlier lines.
    fn y(&self) -> i32 {
        self.height + if self.rows > 0 { self.spacing } else { 0 }
    }

    fn extend_line(&mut self, outer: Size) {
        self.x += outer.width;
        self.width = self.width.max(self.x);
        self.line_height = self.line_height.max(outer.height);
        self.line_open = true;
    }

    fn end_line(&mut self) {
        if self.line_open {
            self.height = self.y() + self.line_height;
            self.rows += 1;
            self.x = 0;
            self.line_height = 0;
            self.line_open = false;
        }
    }
}

#[cfg(test)]
mod tests {
    use super::super::testing::*;
    use crate::engine::style::Display;
    use crate::engine::tree::{Size, Tree};

    #[test]
    fn stacks_blocks_and_keeps_inline_runs_on_one_line() {
        let mut tree = Tree::default();
        let a = text(&mut tree, 1, "aa");
        let b = text(&mut tree, 2, "bb");
        let label = text(&mut tree, 3, "block");
        let inner = element(&mut tree, 4, Display::Block, &[label]);
        let c = text(&mut tree, 5, "cc");
        let root = element(&mut tree, 6, Display::Block, &[a, b, inner, c]);

        assert_eq!(
            measure(&mut tree, root, 10),
            Size {
                width: 10,
                height: 3
            }
        );
        assert_eq!(tree.node(b).geometry.x, 2);
        assert_eq!(tree.node(inner).geometry.y, 1);
        assert_eq!(tree.node(c).geometry.y, 2);
    }

    #[test]
    fn spacing_separates_lines_but_not_the_ends() {
        let mut tree = Tree::default();
        let a = text(&mut tree, 1, "a");
        let first = element(&mut tree, 2, Display::Block, &[a]);
        let b = text(&mut tree, 3, "b");
        let second = element(&mut tree, 4, Display::Block, &[b]);
        let root = element(&mut tree, 5, Display::Block, &[first, second]);
        tree.node_mut(root).style.spacing = 2;

        assert_eq!(measure(&mut tree, root, 10).height, 4);
        assert_eq!(tree.node(second).geometry.y, 3);
    }

    #[test]
    fn empty_blocks_take_no_rows() {
        let mut tree = Tree::default();
        let empty = element(&mut tree, 1, Display::Block, &[]);
        let root = element(&mut tree, 2, Display::Block, &[empty]);

        assert_eq!(measure(&mut tree, root, 10).height, 0);
    }

    #[test]
    fn contents_children_flow_in_the_parent() {
        let mut tree = Tree::default();
        let a = text(&mut tree, 1, "aa");
        let group = element(&mut tree, 2, Display::Contents, &[a]);
        let b = text(&mut tree, 3, "bb");
        let root = element(&mut tree, 4, Display::Block, &[group, b]);

        measure(&mut tree, root, 10);

        assert_eq!(tree.node(b).geometry.x, 2);
    }
}
