//! Retained node tree, stored in a slab.
//!
//! Clients name nodes with ids of their own choosing, so creating a node needs
//! no answer from the engine. Inside the tree nodes link by slab index, which
//! is what layout and paint use.

use super::layout::Constraints;
use super::style::{Display, Position, Style, WhiteSpace};
use std::collections::{BTreeSet, HashMap};

pub type ClientId = u32;
pub type Index = u32;

#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub struct Size {
    pub width: i32,
    pub height: i32,
}

/// Margins that collapse into one, as CSS vertical margins between blocks:
/// the largest positive one plus the most negative one.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub struct Collapse {
    positive: i32,
    negative: i32,
}

impl Collapse {
    pub fn of(margin: i32) -> Self {
        Collapse {
            positive: margin.max(0),
            negative: margin.min(0),
        }
    }

    /// This margin collapsed with another.
    pub fn with(self, other: Collapse) -> Self {
        Collapse {
            positive: self.positive.max(other.positive),
            negative: self.negative.min(other.negative),
        }
    }

    /// The space the margins leave between what they separate.
    pub fn value(self) -> i32 {
        self.positive + self.negative
    }
}

/// Layout results. Offsets are relative to the parent's content box.
#[derive(Debug, Clone, Copy, Default)]
pub struct Geometry {
    pub x: i32,
    pub y: i32,
    pub content: Size,
    pub outer: Size,
    /// Last in-flow line baseline, relative to the content origin.
    pub baseline: Option<i32>,
    /// The top and bottom margins as a block parent sees them, with those of
    /// first and last children that collapse through this node.
    pub margin_top: Collapse,
    pub margin_bottom: Collapse,
    /// Whether this node is empty, so its top and bottom margins collapse
    /// into one, which `margin_top` and `margin_bottom` then both hold.
    pub collapses_through: bool,
    /// Constraints of the last layout, for cache checks.
    pub constraints: Option<Constraints>,
}

/// A piece of a wrapped node on one line. Offsets are from the node's origin.
/// Text uses `start` and `end` as a byte range of its text.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Fragment {
    pub x: i32,
    pub y: i32,
    pub width: i32,
    pub start: u32,
    pub end: u32,
}

/// A run of drawn cells in a canvas row.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct CanvasRun {
    /// First cell, relative to the canvas's content left.
    pub start: i32,
    pub text: String,
    pub width: i32,
    /// Width of each non ASCII character, when any differs from one.
    pub cells: Option<Box<[u8]>>,
}

/// One row of a canvas, painted straight onto the frame without layout.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct CanvasRow {
    /// What the row draws, left to right. An opaque canvas sends one run from
    /// its left edge; a transparent one only the cells it drew.
    pub runs: Vec<CanvasRun>,
    /// Highlight ranges `(start, end, hl)` in cells, relative to the canvas's content left.
    pub ranges: Vec<(i32, i32, u32)>,
}

/// A 2D cell surface owned by a canvas node. Updating its contents never runs
/// layout as long as its dimensions stay the same.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct Canvas {
    pub width: i32,
    pub height: i32,
    /// Cells it did not draw show what is under it and pass presses through.
    pub transparent: bool,
    pub rows: Vec<CanvasRow>,
}

#[cfg(test)]
impl CanvasRow {
    /// One run of ASCII from the left edge, as an opaque canvas sends it.
    pub fn opaque(text: &str, ranges: Vec<(i32, i32, u32)>) -> Self {
        CanvasRow {
            runs: vec![CanvasRun {
                start: 0,
                text: text.into(),
                width: text.len() as i32,
                cells: None,
            }],
            ranges,
        }
    }
}

impl Canvas {
    /// Whether the canvas drew the cell at `col`, `row` of its content box.
    pub fn drew(&self, col: i32, row: i32) -> bool {
        usize::try_from(row)
            .ok()
            .and_then(|row| self.rows.get(row))
            .is_some_and(|line| {
                line.runs
                    .iter()
                    .any(|run| col >= run.start && col < run.start + run.width)
            })
    }
}

#[derive(Debug)]
pub struct Node {
    pub client: ClientId,
    pub display: Display,
    pub style: Style,
    pub text: String,
    /// Display width of `text`, measured by Neovim when it is not ASCII.
    pub text_width: i32,
    /// Width of each non ASCII character, for line breaking.
    pub cells: Option<Box<[u8]>>,
    /// Set when line breaking cut this node into pieces.
    pub fragments: Option<Vec<Fragment>>,
    /// Pre-drawn cell surface for `Display::Canvas` nodes.
    pub canvas: Option<Box<Canvas>>,
    pub parent: Option<Index>,
    pub children: Vec<Index>,
    pub dirty: bool,
    pub geometry: Geometry,
    /// Sizes found for other constraints since the node was last dirty.
    pub memo: Vec<(Constraints, Memo)>,
    /// How the node was last placed, put aside while a sizing pass answers
    /// from `memo`: nothing under it moved, so placing it the same way again
    /// takes this back rather than laying it all out anew.
    pub placed: Option<(Constraints, Memo)>,
}

/// What a measure leaves for its parent, kept so sizing again is free.
#[derive(Debug, Clone, Copy)]
pub struct Memo {
    pub content: Size,
    pub outer: Size,
    pub baseline: Option<i32>,
    pub margin_top: Collapse,
    pub margin_bottom: Collapse,
    pub collapses_through: bool,
}

impl Memo {
    /// What `geometry` leaves for the parent.
    pub fn of(geometry: &Geometry) -> Self {
        Memo {
            content: geometry.content,
            outer: geometry.outer,
            baseline: geometry.baseline,
            margin_top: geometry.margin_top,
            margin_bottom: geometry.margin_bottom,
            collapses_through: geometry.collapses_through,
        }
    }
}

impl Geometry {
    /// Leaves what `memo` kept for the parent, as a measure would.
    pub fn restore(&mut self, memo: &Memo) {
        self.content = memo.content;
        self.outer = memo.outer;
        self.baseline = memo.baseline;
        self.margin_top = memo.margin_top;
        self.margin_bottom = memo.margin_bottom;
        self.collapses_through = memo.collapses_through;
    }
}

#[derive(Debug, PartialEq, Eq)]
pub enum TreeError {
    UnknownNode(ClientId),
    DuplicateNode(ClientId),
    WouldCycle(ClientId),
}

impl std::fmt::Display for TreeError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            TreeError::UnknownNode(id) => write!(f, "unknown node {id}"),
            TreeError::DuplicateNode(id) => write!(f, "node {id} already exists"),
            TreeError::WouldCycle(id) => write!(f, "inserting node {id} would create a cycle"),
        }
    }
}

#[derive(Debug, Default)]
pub struct Tree {
    slots: Vec<Option<Node>>,
    free: Vec<Index>,
    ids: HashMap<ClientId, Index>,
    /// Out of flow nodes, kept apart so plain trees never look for them.
    absolutes: BTreeSet<Index>,
    /// Set while a node is only sized, not placed.
    pub sizing: bool,
    /// Nodes laid out, counted for the frame stats.
    pub arranged: usize,
}

impl Tree {
    pub fn node(&self, index: Index) -> &Node {
        self.slots[index as usize]
            .as_ref()
            .expect("stale node index")
    }

    pub fn node_mut(&mut self, index: Index) -> &mut Node {
        self.slots[index as usize]
            .as_mut()
            .expect("stale node index")
    }

    pub fn index_of(&self, client: ClientId) -> Result<Index, TreeError> {
        self.ids
            .get(&client)
            .copied()
            .ok_or(TreeError::UnknownNode(client))
    }

    pub fn len(&self) -> usize {
        self.ids.len()
    }

    pub fn is_empty(&self) -> bool {
        self.ids.is_empty()
    }

    pub fn absolutes(&self) -> &BTreeSet<Index> {
        &self.absolutes
    }

    /// Absolute nodes that have a parent to be placed against. One created but
    /// not inserted yet, as when a mount fails halfway, would be its own
    /// containing block, and finding where it is would never end.
    pub fn attached_absolutes(&self) -> impl Iterator<Item = Index> + '_ {
        self.absolutes
            .iter()
            .copied()
            .filter(|&index| self.node(index).parent.is_some())
    }

    /// Call after a style change, to keep `absolutes` current.
    pub fn sync_position(&mut self, index: Index) {
        if self.node(index).style.position() == Position::Absolute {
            self.absolutes.insert(index);
        } else {
            self.absolutes.remove(&index);
        }
    }

    /// The box an absolute node is placed against: its nearest positioned
    /// ancestor, or the root.
    pub fn containing_block(&self, index: Index) -> Index {
        let mut current = index;
        while let Some(parent) = self.node(current).parent {
            let node = self.node(parent);
            let positioned = node.style.position() != Position::Static;
            if node.parent.is_none() || (positioned && node.display != Display::Contents) {
                return parent;
            }
            current = parent;
        }
        current
    }

    /// Top left of a node's margin box, in buffer cells.
    pub fn origin(&self, index: Index) -> (i32, i32) {
        let node = self.node(index);
        let geometry = &node.geometry;

        if node.style.position() == Position::Absolute {
            let block = self.containing_block(index);
            let (x, y) = self.origin(block);
            let margin = self.node(block).style.margin;
            return (x + margin.left + geometry.x, y + margin.top + geometry.y);
        }

        let own_shift = node.style.relative_offset();
        let mut parent = node.parent;
        while let Some(index) = parent {
            let node = self.node(index);
            if node.display != Display::Contents {
                let (x, y) = self.origin(index);
                let style = &node.style;
                let (shift_x, shift_y) = own_shift;
                return (
                    x + style.margin.left + style.inner().left + geometry.x + shift_x,
                    y + style.margin.top + style.inner().top + geometry.y + shift_y,
                );
            }
            parent = node.parent;
        }

        (geometry.x, geometry.y)
    }

    pub fn create(&mut self, client: ClientId, display: Display) -> Result<Index, TreeError> {
        if self.ids.contains_key(&client) {
            return Err(TreeError::DuplicateNode(client));
        }

        let node = Node {
            client,
            display,
            style: Style::default(),
            text: String::new(),
            text_width: 0,
            cells: None,
            fragments: None,
            canvas: None,
            parent: None,
            children: Vec::new(),
            dirty: true,
            geometry: Geometry::default(),
            memo: Vec::new(),
            placed: None,
        };

        let index = match self.free.pop() {
            Some(index) => {
                self.slots[index as usize] = Some(node);
                index
            }
            None => {
                self.slots.push(Some(node));
                (self.slots.len() - 1) as Index
            }
        };

        self.ids.insert(client, index);
        Ok(index)
    }

    /// Marks a node and its ancestors for layout. Stops at a dirty node whose
    /// parent is dirty too, because everything above it is already marked.
    /// `Contents` nodes never go through layout, so their flag proves nothing.
    pub fn mark_dirty(&mut self, index: Index) {
        let mut current = Some(index);
        while let Some(index) = current {
            let node = self.node(index);
            let parent = node.parent;
            let settled = node.dirty && node.display != Display::Contents;
            // A dirty parent means the rest of the way up is dirty too, but
            // not when it is contents: nothing lays those out, so they stay
            // dirty however clean everything above them is.
            let parent_settled = parent.is_some_and(|p| {
                let parent = self.node(p);
                parent.dirty && parent.display != Display::Contents
            });
            if settled && parent_settled {
                return;
            }
            self.node_mut(index).dirty = true;
            current = parent;
        }
    }

    /// Whether text under a node may wrap, from the nearest `white_space`.
    pub fn text_wraps(&self, index: Index) -> bool {
        let mut current = Some(index);
        while let Some(index) = current {
            let node = self.node(index);
            if let Some(white_space) = node.style.extra().white_space {
                return white_space == WhiteSpace::Normal;
            }
            current = node.parent;
        }
        true
    }

    /// Marks a whole subtree, for changes that its descendants inherit.
    pub fn mark_subtree_dirty(&mut self, index: Index) {
        let mut stack = vec![index];
        while let Some(index) = stack.pop() {
            let node = self.node_mut(index);
            node.dirty = true;
            stack.extend(node.children.iter().copied());
        }
        self.mark_dirty(index);
    }

    /// Inserts `child` into `parent` before `before`, or last without one.
    /// A child that already has a parent is moved.
    pub fn insert(
        &mut self,
        parent: Index,
        child: Index,
        before: Option<Index>,
    ) -> Result<(), TreeError> {
        let mut ancestor = Some(parent);
        while let Some(index) = ancestor {
            if index == child {
                return Err(TreeError::WouldCycle(self.node(child).client));
            }
            ancestor = self.node(index).parent;
        }

        self.detach(child);

        let children = &self.node(parent).children;
        // Most inserts land near the end, so search backwards.
        let position = before
            .and_then(|before| children.iter().rposition(|&c| c == before))
            .unwrap_or(children.len());

        self.node_mut(parent).children.insert(position, child);
        self.node_mut(child).parent = Some(parent);
        self.mark_dirty(parent);
        Ok(())
    }

    fn detach(&mut self, child: Index) {
        if let Some(parent) = self.node_mut(child).parent.take() {
            let children = &mut self.node_mut(parent).children;
            if let Some(position) = children.iter().rposition(|&c| c == child) {
                children.remove(position);
            }
            self.mark_dirty(parent);
        }
    }

    /// Detaches a node and frees it with its whole subtree.
    pub fn remove(&mut self, index: Index) {
        self.detach(index);
        self.free_subtree(index);
    }

    /// Frees every child of a node, keeping the node itself.
    pub fn clear(&mut self, index: Index) {
        for child in std::mem::take(&mut self.node_mut(index).children) {
            self.free_subtree(child);
        }
        self.mark_dirty(index);
    }

    fn free_subtree(&mut self, root: Index) {
        let mut stack = vec![root];
        while let Some(index) = stack.pop() {
            let Some(node) = self.slots[index as usize].take() else {
                continue;
            };
            stack.extend(node.children);
            self.ids.remove(&node.client);
            self.absolutes.remove(&index);
            self.free.push(index);
        }
    }

    /// Calls `visit` for each child that takes part in flow, looking through
    /// `Contents` nodes and skipping absolute ones. Indexes into the list, so
    /// `visit` may mutate the tree.
    pub fn for_each_flow_child(
        &mut self,
        index: Index,
        reverse: bool,
        visit: &mut impl FnMut(&mut Tree, Index),
    ) {
        let len = self.node(index).children.len();
        for position in 0..len {
            let position = if reverse {
                len - 1 - position
            } else {
                position
            };
            let child = self.node(index).children[position];
            let node = self.node(child);
            if node.display == Display::Contents {
                self.for_each_flow_child(child, reverse, visit);
            } else if node.style.position() != Position::Absolute {
                visit(self, child);
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn tree_with(ids: &[ClientId]) -> (Tree, Vec<Index>) {
        let mut tree = Tree::default();
        let indexes = ids
            .iter()
            .map(|&id| tree.create(id, Display::Block).unwrap())
            .collect();
        (tree, indexes)
    }

    #[test]
    fn insert_moves_a_child_that_has_a_parent() {
        let (mut tree, n) = tree_with(&[1, 2, 3]);
        tree.insert(n[0], n[1], None).unwrap();
        tree.insert(n[2], n[1], None).unwrap();

        assert!(tree.node(n[0]).children.is_empty());
        assert_eq!(tree.node(n[2]).children, vec![n[1]]);
    }

    #[test]
    fn insert_before_keeps_order() {
        let (mut tree, n) = tree_with(&[1, 2, 3, 4]);
        tree.insert(n[0], n[1], None).unwrap();
        tree.insert(n[0], n[2], None).unwrap();
        tree.insert(n[0], n[3], Some(n[2])).unwrap();

        assert_eq!(tree.node(n[0]).children, vec![n[1], n[3], n[2]]);
    }

    #[test]
    fn insert_rejects_cycles() {
        let (mut tree, n) = tree_with(&[1, 2]);
        tree.insert(n[0], n[1], None).unwrap();

        assert_eq!(tree.insert(n[1], n[0], None), Err(TreeError::WouldCycle(1)));
    }

    #[test]
    fn remove_frees_the_subtree_and_its_ids() {
        let (mut tree, n) = tree_with(&[1, 2, 3]);
        tree.insert(n[0], n[1], None).unwrap();
        tree.insert(n[1], n[2], None).unwrap();
        tree.remove(n[1]);

        assert_eq!(tree.len(), 1);
        assert_eq!(tree.index_of(3), Err(TreeError::UnknownNode(3)));
        assert!(tree.create(3, Display::Block).is_ok());
    }

    #[test]
    fn mark_dirty_reaches_the_root_through_a_dirty_child() {
        let (mut tree, n) = tree_with(&[1, 2, 3]);
        tree.insert(n[0], n[1], None).unwrap();
        tree.insert(n[1], n[2], None).unwrap();
        for &index in &n {
            tree.node_mut(index).dirty = false;
        }

        tree.node_mut(n[2]).dirty = true;
        tree.mark_dirty(n[2]);

        assert!(tree.node(n[0]).dirty);
    }

    #[test]
    fn mark_dirty_passes_through_nested_contents() {
        let mut tree = Tree::default();
        let root = tree.create(1, Display::Block).unwrap();
        let outer = tree.create(2, Display::Contents).unwrap();
        let inner = tree.create(3, Display::Contents).unwrap();
        tree.insert(root, outer, None).unwrap();
        tree.insert(outer, inner, None).unwrap();

        // Layout skips contents nodes, so only real nodes get cleaned.
        tree.node_mut(root).dirty = false;

        let child = tree.create(4, Display::Block).unwrap();
        tree.insert(inner, child, None).unwrap();

        assert!(tree.node(root).dirty);
    }

    #[test]
    fn a_dirty_node_under_stale_contents_still_reaches_the_root() {
        let mut tree = Tree::default();
        let root = tree.create(1, Display::Block).unwrap();
        let group = tree.create(2, Display::Contents).unwrap();
        let child = tree.create(3, Display::Block).unwrap();
        tree.insert(root, group, None).unwrap();
        tree.insert(group, child, None).unwrap();

        // After a layout the group is still dirty, as nothing measures it.
        tree.node_mut(root).dirty = false;
        tree.node_mut(child).dirty = false;

        tree.mark_subtree_dirty(child);

        assert!(tree.node(root).dirty);
    }

    #[test]
    fn flow_children_look_through_contents() {
        let mut tree = Tree::default();
        let root = tree.create(1, Display::Block).unwrap();
        let group = tree.create(2, Display::Contents).unwrap();
        let a = tree.create(3, Display::Block).unwrap();
        let b = tree.create(4, Display::Block).unwrap();
        tree.insert(root, group, None).unwrap();
        tree.insert(group, a, None).unwrap();
        tree.insert(root, b, None).unwrap();

        let mut seen = Vec::new();
        tree.for_each_flow_child(root, false, &mut |_, child| seen.push(child));

        assert_eq!(seen, vec![a, b]);
    }
}
