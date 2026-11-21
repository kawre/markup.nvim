use super::{Space, Strategy, measure, place, wrap};
use crate::engine::style::{Display, Length};
use crate::engine::tree::{Collapse, Index, Size, Tree};

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
        let size = wrap::flow(tree, run, limit, space.width, !space.whole_words);
        for &child in run.iter() {
            // Pieces of a wrapped inline are placed from the run's origin; an
            // inline-block is one piece, placed where the flow put it.
            let entry = tree.node(child);
            if super::is_inline_block(&entry.style) {
                let (x, y) = (entry.geometry.x, entry.geometry.y);
                place(tree, child, x, top + y);
            } else {
                place(tree, child, 0, top);
            }
        }
        cursor.extend_line(size);
    } else {
        // Laid out plainly: what an earlier wrap left on them no longer holds,
        // even where they kept their layout.
        for &child in run.iter() {
            tree.node_mut(child).fragments = None;
        }
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
        let through = Through::of(tree, node, space);

        let mut cursor = Cursor {
            spacing,
            ..Cursor::default()
        };
        let mut run = Vec::new();
        // Margins that meet where the next line or block starts, as CSS
        // collapses them into one.
        let mut pending = Collapse::default();
        // Whether a line or a block's border is in place yet: until one is,
        // margins can pass through this node's top.
        let mut started = false;
        let mut through_top = Collapse::default();

        // Puts down the margins that meet where content starts.
        let mut open = |cursor: &mut Cursor, pending: &mut Collapse, started: &mut bool| {
            if !*started && through.top {
                through_top = *pending;
            } else {
                cursor.height += pending.value();
            }
            *pending = Collapse::default();
            *started = true;
        };

        tree.for_each_flow_child(node, reverse, &mut |tree, child| {
            if tree.node(child).display.is_inline() {
                run.push(child);
                return;
            }
            if !run.is_empty() {
                open(&mut cursor, &mut pending, &mut started);
                flush_run(tree, &mut run, &mut cursor, space, wraps);
            }

            let outer = measure(tree, child, space.child(space.width));
            let entry = tree.node(child);
            let geometry = entry.geometry;
            let margin = entry.style.margin;
            let before = pending;
            pending = pending.with(geometry.margin_top);

            if geometry.collapses_through {
                // Empty: its margins join the ones around it. As CSS places it:
                // at the top when they pass through this node, or else past
                // the margins above it, as if it had a bottom border.
                let past = if !started && through.top {
                    0
                } else {
                    // Past the margins above and its own top one, not the
                    // bottom one it meets.
                    before.with(Collapse::of(margin.top)).value()
                };
                place(tree, child, 0, cursor.y() + past - margin.top);
                pending = pending.with(geometry.margin_bottom);
                return;
            }

            open(&mut cursor, &mut pending, &mut started);
            let top = cursor.y();
            place(tree, child, 0, top - margin.top);
            cursor.extend_line(Size {
                width: outer.width,
                height: outer.height - margin.top - margin.bottom,
            });
            cursor.end_line();
            pending = geometry.margin_bottom;
        });

        if !run.is_empty() {
            open(&mut cursor, &mut pending, &mut started);
            flush_run(tree, &mut run, &mut cursor, space, wraps);
        }

        let own = tree.node(node).style.margin;
        let geometry = &mut tree.node_mut(node).geometry;
        if !started && through.empty {
            // Nothing holds the margins apart: all of them are one.
            let all = Collapse::of(own.top)
                .with(pending)
                .with(Collapse::of(own.bottom));
            geometry.margin_top = all;
            geometry.margin_bottom = all;
            geometry.collapses_through = true;
        } else {
            geometry.margin_top = Collapse::of(own.top).with(through_top);
            if started && through.bottom {
                geometry.margin_bottom = Collapse::of(own.bottom).with(pending);
            } else {
                cursor.height += pending.value();
            }
        }

        Size {
            width: cursor.width,
            height: cursor.height,
        }
    }
}

/// Which margins of its children a block lets through, as CSS collapses
/// them with its own. A box that starts a formatting context of its own, the
/// root, or one with padding or a border on that side keeps them inside.
struct Through {
    top: bool,
    bottom: bool,
    /// Whether, with nothing in it, its own top and bottom margins meet.
    empty: bool,
}

impl Through {
    fn of(tree: &Tree, node: Index, space: Space) -> Self {
        let entry = tree.node(node);
        let style = &entry.style;
        let extra = style.extra();
        let mut parent = entry.parent;
        let mut in_flow = parent.is_some();
        while let Some(index) = parent {
            match tree.node(index).display {
                Display::Contents => parent = tree.node(index).parent,
                display => {
                    in_flow = !matches!(display, Display::Flex | Display::Grid);
                    break;
                }
            }
        }
        // As CSS: `overflow: hidden` starts a formatting context, `clip` does
        // not. A flex or grid item is in one of its parent's.
        let open = in_flow && !extra.scrolls;
        let block = open && entry.display == Display::Block;
        let inner = style.inner();
        let auto_height = style.height == Length::Auto && space.height.is_none();
        // As browsers do: a height or min_height of 0 still lets them meet.
        let zero = |length: Length| matches!(length, Length::Auto | Length::Cells(0));
        let empty = block
            && inner.top == 0
            && inner.bottom == 0
            && zero(style.height)
            && space.height.is_none_or(|height| height == 0)
            && zero(extra.min_height);
        Through {
            top: block && inner.top == 0,
            bottom: block && inner.bottom == 0 && auto_height,
            empty,
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
