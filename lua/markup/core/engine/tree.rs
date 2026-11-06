//! Retained node tree, stored in a slab.
//!
//! Clients name nodes with ids of their own choosing, so creating a node needs
//! no answer from the engine. Inside the tree nodes link by slab index, which
//! is what layout and paint use.

use super::layout::Constraints;
use super::style::{Display, Position, Style};
use std::collections::{BTreeSet, HashMap};

pub type ClientId = u32;
pub type Index = u32;

#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub struct Size {
    pub width: i32,
    pub height: i32,
}

/// Layout results. Offsets are relative to the parent's content box.
#[derive(Debug, Clone, Copy, Default)]
pub struct Geometry {
    pub x: i32,
    pub y: i32,
    pub content: Size,
    pub outer: Size,
    /// Constraints of the last layout, for cache checks.
    pub constraints: Option<Constraints>,
}

#[derive(Debug)]
pub struct Node {
    pub client: ClientId,
    pub display: Display,
    pub style: Style,
    pub text: String,
    /// Display width of `text`, measured by Neovim when it is not ASCII.
    pub text_width: i32,
    pub parent: Option<Index>,
    pub children: Vec<Index>,
    pub dirty: bool,
    pub geometry: Geometry,
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
}

impl Tree {
    pub fn node(&self, index: Index) -> &Node {
        self.slots[index as usize].as_ref().expect("stale node index")
    }

    pub fn node_mut(&mut self, index: Index) -> &mut Node {
        self.slots[index as usize].as_mut().expect("stale node index")
    }

    pub fn index_of(&self, client: ClientId) -> Result<Index, TreeError> {
        self.ids.get(&client).copied().ok_or(TreeError::UnknownNode(client))
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
            parent: None,
            children: Vec::new(),
            dirty: true,
            geometry: Geometry::default(),
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
            if settled && parent.is_some_and(|p| self.node(p).dirty) {
                return;
            }
            self.node_mut(index).dirty = true;
            current = parent;
        }
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
            let position = if reverse { len - 1 - position } else { position };
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
        let indexes = ids.iter().map(|&id| tree.create(id, Display::Block).unwrap()).collect();
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
