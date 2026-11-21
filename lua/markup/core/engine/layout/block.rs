use super::wrap::RunItem;
use super::{Space, Strategy, is_inline_block, measure, place, wrap};
use crate::engine::style::{Display, Length};
use crate::engine::tree::{Collapse, Index, Size, Tree};
use std::collections::HashMap;

/// What a block lays out, in order, once inlines that hold blocks are split
/// around them as CSS splits them.
enum Event {
    /// Inline content: text, an inline, an inline-block.
    Inline(Index),
    /// An inline split around the blocks in it: where it starts and ends.
    Open(Index),
    Close(Index),
    Block(Index),
}

/// Whether an inline holds a block in its flow, so CSS splits it around it.
fn holds_block(tree: &mut Tree, node: Index) -> bool {
    let mut found = false;
    tree.for_each_flow_child(node, false, &mut |tree, child| {
        let entry = tree.node(child);
        found = found
            || !entry.display.is_inline()
            || (entry.display == Display::Inline
                && !is_inline_block(&entry.style)
                && holds_block(tree, child));
    });
    found
}

fn events(tree: &mut Tree, node: Index, out: &mut Vec<Event>) {
    let reverse = tree.node(node).style.reverse;
    let mut children = Vec::new();
    tree.for_each_flow_child(node, reverse, &mut |_, child| children.push(child));
    for child in children {
        let entry = tree.node(child);
        if !entry.display.is_inline() {
            out.push(Event::Block(child));
        } else if entry.display == Display::Inline
            && !is_inline_block(&entry.style)
            && holds_block(tree, child)
        {
            out.push(Event::Open(child));
            events(tree, child, out);
            out.push(Event::Close(child));
        } else {
            out.push(Event::Inline(child));
        }
    }
}

/// The parts of inlines split around blocks: where each starts, in this
/// block's content box, and what it sits in.
#[derive(Default)]
struct Split {
    /// Top of each split inline's first part, which is its origin's row.
    tops: HashMap<Index, i32>,
    /// The split inline each one sits in, if any.
    parents: HashMap<Index, Index>,
}

impl Split {
    /// Where a split inline's content starts, in this block's content box.
    fn content(&self, tree: &Tree, node: Index) -> (i32, i32) {
        let style = &tree.node(node).style;
        let (margin, inner) = (style.margin, style.inner());
        (
            margin.left + inner.left,
            self.tops[&node] + margin.top + inner.top,
        )
    }

    /// Moves a node placed in this block's content box into the content box of
    /// the split inline it sits in.
    fn place(&self, tree: &mut Tree, parent: Option<Index>, node: Index, x: i32, y: i32) {
        let (left, top) = parent.map_or((0, 0), |parent| self.content(tree, parent));
        place(tree, node, x - left, y - top);
    }
}

/// Places a run that holds parts of split inlines. It always flows: each part
/// needs to know where its pieces landed.
fn flush_parts(
    tree: &mut Tree,
    run: &mut Vec<RunItem>,
    split: &mut Split,
    cursor: &mut Cursor,
    space: Space,
    wraps: bool,
) {
    let top = cursor.y();
    let mut stack: Vec<Index> = Vec::new();
    let mut content = false;
    for item in run.iter_mut() {
        match item {
            RunItem::Open { node, first, base } => {
                if *first {
                    // The first part: the inline's origin is the start of
                    // this row, in the content box of what it sits in.
                    split.tops.insert(*node, top);
                    if let Some(&parent) = stack.last() {
                        split.parents.insert(*node, parent);
                    }
                    let parent = split.parents.get(node).copied();
                    split.place(tree, parent, *node, 0, top);
                    tree.node_mut(*node).fragments = Some(Vec::new());
                    let style = &tree.node(*node).style;
                    content |= style.margin.left + style.inner().left > 0;
                }
                *base = (0, split.tops[node] - top);
                stack.push(*node);
            }
            RunItem::Close { node, last } => {
                stack.pop();
                if *last {
                    let style = &tree.node(*node).style;
                    content |= style.margin.right + style.inner().right > 0;
                }
            }
            RunItem::Node(_) => content = true,
        }
    }

    // As CSS: a line with nothing on it, not even an edge, takes no row.
    if content {
        let limit = if wraps && space.can_wrap() {
            space.width
        } else {
            i32::MAX
        };
        let size = wrap::flow_items(tree, run, limit, space.width, !space.whole_words);
        // What sits outside the split inlines is placed from the run's origin,
        // as in any run; what is inside them, the flow placed.
        let mut depth = 0;
        for item in run.iter() {
            match *item {
                RunItem::Open { .. } => depth += 1,
                RunItem::Close { .. } => depth -= 1,
                RunItem::Node(child) if depth == 0 => {
                    let entry = tree.node(child);
                    if is_inline_block(&entry.style) {
                        let (x, y) = (entry.geometry.x, entry.geometry.y);
                        place(tree, child, x, top + y);
                    } else {
                        place(tree, child, 0, top);
                    }
                }
                RunItem::Node(_) => {}
            }
        }
        cursor.extend_line(size);
        cursor.end_line();
    }
    run.clear();
}

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
        // As CSS: an inline-block holds its line open, empty as it may be.
        if is_inline_block(&tree.node(child).style) {
            height = height.max(1);
        }
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
        let spacing = style.spacing;
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

        let mut stream = Vec::new();
        events(tree, node, &mut stream);
        let mut parts: Vec<RunItem> = Vec::new();
        let mut split = Split::default();
        // The split inlines open where the next event is, outermost first.
        let mut inside: Vec<Index> = Vec::new();

        for event in stream {
            let child = match event {
                Event::Inline(child) => {
                    if parts.is_empty() {
                        run.push(child);
                    } else {
                        parts.push(RunItem::Node(child));
                    }
                    continue;
                }
                Event::Open(inline) => {
                    parts.extend(run.drain(..).map(RunItem::Node));
                    parts.push(RunItem::Open {
                        node: inline,
                        first: true,
                        base: (0, 0),
                    });
                    inside.push(inline);
                    continue;
                }
                Event::Close(inline) => {
                    inside.pop();
                    parts.push(RunItem::Close {
                        node: inline,
                        last: true,
                    });
                    continue;
                }
                Event::Block(child) => child,
            };

            // A block ends the line, closing the inlines it sits in for now.
            for &inline in inside.iter().rev() {
                parts.push(RunItem::Close {
                    node: inline,
                    last: false,
                });
            }
            if !parts.is_empty() {
                parts.extend(run.drain(..).map(RunItem::Node));
                open(&mut cursor, &mut pending, &mut started);
                flush_parts(tree, &mut parts, &mut split, &mut cursor, space, wraps);
            } else if !run.is_empty() {
                open(&mut cursor, &mut pending, &mut started);
                flush_run(tree, &mut run, &mut cursor, space, wraps);
            }
            let sits_in = inside.last().copied();

            let outer = measure(tree, child, space.child(space.width));
            let entry = tree.node(child);
            let geometry = entry.geometry;
            let margin = entry.style.margin;
            if spacing > 0 && cursor.rows > 0 {
                // `spacing` is a row of its own between rows, which the
                // margins on either side of it do not meet across.
                cursor.height += pending.value();
                pending = Collapse::default();
            }
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
                split.place(tree, sits_in, child, 0, cursor.y() + past - margin.top);
                pending = pending.with(geometry.margin_bottom);
            } else {
                open(&mut cursor, &mut pending, &mut started);
                let top = cursor.y();
                split.place(tree, sits_in, child, 0, top - margin.top);
                cursor.extend_line(Size {
                    width: outer.width,
                    height: outer.height - margin.top - margin.bottom,
                });
                cursor.end_line();
                pending = geometry.margin_bottom;
            }

            // The inlines go on after it, on a line of their own.
            for &inline in &inside {
                parts.push(RunItem::Open {
                    node: inline,
                    first: false,
                    base: (0, 0),
                });
            }
        }

        if !parts.is_empty() {
            parts.extend(run.drain(..).map(RunItem::Node));
            open(&mut cursor, &mut pending, &mut started);
            flush_parts(tree, &mut parts, &mut split, &mut cursor, space, wraps);
        } else if !run.is_empty() {
            open(&mut cursor, &mut pending, &mut started);
            flush_run(tree, &mut run, &mut cursor, space, wraps);
        }

        // A split inline covers from its first part to here.
        for (&inline, &top) in &split.tops {
            let entry = tree.node_mut(inline);
            let size = Size {
                width: space.width,
                height: (cursor.height - top).max(0),
            };
            entry.geometry.content = size;
            entry.geometry.outer = size;
            entry.geometry.constraints = None;
            entry.dirty = false;
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
        // not, and so does an absolute box. A flex or grid item is in one of
        // its parent's.
        let absolute = style.position() == crate::engine::style::Position::Absolute;
        let open = in_flow && !extra.scrolls && !absolute;
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
