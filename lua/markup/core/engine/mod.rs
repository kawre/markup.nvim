//! The engine applies commands to the tree and reports what changed on screen.

pub mod cursor;
pub mod diff;
pub mod inspect;
pub mod layout;
pub mod lua;
pub mod paint;
pub mod protocol;
pub mod style;
pub mod tree;
mod visible;

use paint::Line;
use protocol::{Command, StyleProperty};
use std::time::Instant;
use style::{Direction, Display, Position};
use tree::{ClientId, Index, Tree, TreeError};

/// Client id of the root node, which exists for the engine's whole life.
pub const ROOT: ClientId = 1;

/// How long each stage of a commit took, in milliseconds.
#[derive(Debug, Default, Clone, Copy)]
pub struct Timings {
    pub layout: f64,
    pub paint: f64,
    pub diff: f64,
}

pub struct Engine {
    tree: Tree,
    root: Index,
    width: i32,
    lines: Vec<Line>,
}

fn elapsed_ms(since: Instant) -> f64 {
    since.elapsed().as_secs_f64() * 1e3
}

impl Engine {
    pub fn new(width: i32) -> Self {
        let mut tree = Tree::default();
        let root = tree
            .create(ROOT, Display::Block)
            .expect("an empty tree has no duplicate ids");

        Engine {
            tree,
            root,
            width,
            lines: vec![Line::default()],
        }
    }

    pub fn tree(&self) -> &Tree {
        &self.tree
    }

    pub fn root_index(&self) -> Index {
        self.root
    }

    /// Forgets the last frame, so the next one is sent in full. For when the
    /// buffer it was written to is gone or has not been written to at all.
    pub fn reset_frame(&mut self) {
        self.lines = vec![Line::default()];
    }

    pub fn apply(&mut self, command: Command) -> Result<(), TreeError> {
        let tree = &mut self.tree;
        match command {
            Command::Create { id, display } => {
                tree.create(id, display)?;
            }
            Command::CreateText { id, text, width } => {
                let index = tree.create(id, Display::Text)?;
                let node = tree.node_mut(index);
                node.text = text;
                node.text_width = width;
            }
            Command::SetText { id, text, width } => {
                let index = tree.index_of(id)?;
                let node = tree.node_mut(index);
                // Wrapped text can break differently at the same total width.
                let relayout = node.text_width != width || node.fragments.is_some();
                node.text = text;
                node.text_width = width;
                node.cells = None;
                if relayout {
                    tree.mark_dirty(index);
                }
            }
            Command::SetStyle { id, property } => {
                let index = tree.index_of(id)?;
                property.apply(&mut tree.node_mut(index).style);
                tree.sync_position(index);
                if matches!(property, StyleProperty::WhiteSpace(_)) {
                    tree.mark_subtree_dirty(index);
                } else {
                    tree.mark_dirty(index);
                }
            }
            Command::SetBorder { id, border } => {
                let index = tree.index_of(id)?;
                tree.node_mut(index).style.extra_mut().border = border;
                tree.mark_dirty(index);
            }
            Command::SetCells { id, cells } => {
                let index = tree.index_of(id)?;
                tree.node_mut(index).cells = Some(cells.into_boxed_slice());
                tree.mark_dirty(index);
            }
            Command::Insert {
                parent,
                child,
                before,
            } => {
                let parent = tree.index_of(parent)?;
                let child = tree.index_of(child)?;
                let before = before.map(|id| tree.index_of(id)).transpose()?;
                tree.insert(parent, child, before)?;
            }
            Command::Remove { id } => {
                let index = tree.index_of(id)?;
                tree.remove(index);
            }
            Command::Clear { id } => {
                let index = tree.index_of(id)?;
                tree.clear(index);
            }
            Command::Resize { width } => {
                self.width = width;
            }
            Command::SetTracks { id, axis, tracks } => {
                let index = tree.index_of(id)?;
                let extra = tree.node_mut(index).style.extra_mut();
                match axis {
                    Direction::Row => extra.rows = tracks,
                    Direction::Column => extra.columns = tracks,
                }
                tree.mark_dirty(index);
            }
        }
        Ok(())
    }

    /// Runs layout, paint and diff, then hands the patches to `emit` before the
    /// new frame replaces the old one.
    pub fn render<T>(&mut self, emit: impl FnOnce(&[diff::Patch], Timings) -> T) -> T {
        let mut timings = Timings::default();

        let started = Instant::now();
        let size = layout::measure(
            &mut self.tree,
            self.root,
            layout::Constraints::available(self.width),
        );
        layout::absolute::layout(&mut self.tree);
        let height = self.height_with_absolutes(size.height);
        timings.layout = elapsed_ms(started);

        let started = Instant::now();
        // A buffer always has a line, so a frame does too.
        let lines = paint::paint(&self.tree, self.root, height.max(1));
        timings.paint = elapsed_ms(started);

        let started = Instant::now();
        let patches = diff::diff(&self.lines, &lines);
        timings.diff = elapsed_ms(started);

        let result = emit(&patches, timings);
        drop(patches);
        self.lines = lines;
        result
    }

    /// Absolute boxes can reach past everything in flow.
    fn height_with_absolutes(&self, height: i32) -> i32 {
        self.tree
            .attached_absolutes()
            .fold(height, |height, index| {
                let bottom = self.origin(index).1 + self.tree.node(index).geometry.outer.height;
                height.max(bottom)
            })
    }

    /// Top left of a node's margin box, in buffer cells.
    pub fn origin(&self, index: Index) -> (i32, i32) {
        let tree = &self.tree;
        let node = tree.node(index);
        let geometry = &node.geometry;

        if node.style.position() == Position::Absolute {
            let block = tree.containing_block(index);
            let (x, y) = self.origin(block);
            let margin = tree.node(block).style.margin;
            return (x + margin.left + geometry.x, y + margin.top + geometry.y);
        }

        let own_shift = node.style.relative_offset();
        let mut parent = node.parent;
        while let Some(index) = parent {
            let node = tree.node(index);
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

    /// Finds the innermost interactive node on a cell. Nothing under an inert
    /// node counts.
    pub fn node_at(&self, row: i32, col: i32) -> Option<ClientId> {
        let mut found = None;
        for id in self.path_at(row, col) {
            let Ok(index) = self.tree.index_of(id) else {
                continue;
            };
            let style = &self.tree.node(index).style;
            if style.extra().inert {
                break;
            }
            if style.interactive {
                found = Some(id);
            }
        }
        found
    }

    /// Every node on a cell, from the root down to the innermost one. Absolute
    /// boxes sit on top, so they are tried first, highest `z` before lower.
    pub fn path_at(&self, row: i32, col: i32) -> Vec<ClientId> {
        let tree = &self.tree;

        let mut overlays: Vec<Index> = tree.attached_absolutes().collect();
        overlays.sort_by_key(|&index| std::cmp::Reverse(tree.node(index).style.extra().z));

        for index in overlays {
            let (x, y) = self.origin(index);
            let mut path = self.ancestors(index);
            if self.descend(index, x, y, row, col, &mut path) {
                return path;
            }
        }

        let mut path = Vec::new();
        self.descend(self.root, 0, 0, row, col, &mut path);
        path
    }

    fn ancestors(&self, index: Index) -> Vec<ClientId> {
        let mut path = Vec::new();
        let mut parent = self.tree.node(index).parent;
        while let Some(index) = parent {
            let node = self.tree.node(index);
            path.push(node.client);
            parent = node.parent;
        }
        path.reverse();
        path
    }

    /// Walks down from a node whose margin box starts at `x`, `y`.
    fn descend(
        &self,
        index: Index,
        x: i32,
        y: i32,
        row: i32,
        col: i32,
        path: &mut Vec<ClientId>,
    ) -> bool {
        let node = self.tree.node(index);
        let outer = node.geometry.outer;

        // A wrapped node only covers its fragments, not its bounding box.
        let inside = match &node.fragments {
            Some(fragments) => fragments.iter().any(|fragment| {
                row == y + fragment.y
                    && col >= x + fragment.x
                    && col < x + fragment.x + fragment.width
            }),
            // The margin is space around the node, not part of it: only its
            // border box takes the cursor and presses.
            None => {
                let margin = node.style.margin;
                let (left, top) = (x + margin.left, y + margin.top);
                let width = outer.width - margin.left - margin.right;
                let height = outer.height - margin.top - margin.bottom;
                row >= top && row < top + height && col >= left && col < left + width.max(1)
            }
        };
        if !inside {
            return false;
        }

        path.push(node.client);
        let style = &node.style;
        let content_x = x + style.margin.left + style.inner().left;
        let content_y = y + style.margin.top + style.inner().top;
        node.children
            .iter()
            .any(|&child| self.descend_child(child, content_x, content_y, row, col, path));
        true
    }

    fn descend_child(
        &self,
        index: Index,
        x: i32,
        y: i32,
        row: i32,
        col: i32,
        path: &mut Vec<ClientId>,
    ) -> bool {
        let node = self.tree.node(index);

        if node.display == Display::Contents {
            path.push(node.client);
            let found = node
                .children
                .iter()
                .any(|&child| self.descend_child(child, x, y, row, col, path));
            if !found {
                path.pop();
            }
            return found;
        }

        if node.style.position() == Position::Absolute {
            return false;
        }

        let (shift_x, shift_y) = node.style.relative_offset();
        self.descend(
            index,
            x + node.geometry.x + shift_x,
            y + node.geometry.y + shift_y,
            row,
            col,
            path,
        )
    }
}

#[cfg(test)]
mod tests {
    use super::protocol::Side;
    use super::style::{Display, Length};
    use super::*;

    fn block(engine: &mut Engine, id: u32, parent: u32, label: &str) {
        let commands = [
            Command::Create {
                id,
                display: Display::Block,
            },
            Command::CreateText {
                id: id + 1000,
                text: label.to_string(),
                width: label.len() as i32,
            },
            Command::Insert {
                parent: id,
                child: id + 1000,
                before: None,
            },
            Command::Insert {
                parent,
                child: id,
                before: None,
            },
        ];
        for command in commands {
            engine.apply(command).unwrap();
        }
    }

    fn patched_lines(engine: &mut Engine) -> usize {
        engine.render(|patches, _| patches.iter().map(|patch| patch.lines.len()).sum())
    }

    #[test]
    fn only_changed_lines_are_reported() {
        let mut engine = Engine::new(20);
        block(&mut engine, 2, ROOT, "one");
        block(&mut engine, 3, ROOT, "two");
        assert_eq!(patched_lines(&mut engine), 2);
        assert_eq!(patched_lines(&mut engine), 0);

        let text = "ONE".to_string();
        engine
            .apply(Command::SetText {
                id: 1002,
                text,
                width: 3,
            })
            .unwrap();
        assert_eq!(patched_lines(&mut engine), 1);
        assert_eq!(patched_lines(&mut engine), 0);
    }

    #[test]
    fn an_empty_tree_keeps_one_line() {
        let mut engine = Engine::new(20);
        block(&mut engine, 2, ROOT, "one");
        engine.render(|_, _| ());
        engine.apply(Command::Clear { id: ROOT }).unwrap();

        let lines = engine.render(|patches, _| {
            patches
                .iter()
                .map(|p| (p.first, p.last, p.lines.len()))
                .collect::<Vec<_>>()
        });

        assert_eq!(lines, vec![(0, 1, 1)]);
    }

    #[test]
    fn unknown_nodes_are_errors_not_panics() {
        let mut engine = Engine::new(20);
        assert_eq!(
            engine.apply(Command::Remove { id: 42 }),
            Err(TreeError::UnknownNode(42))
        );
    }

    #[test]
    fn node_at_finds_the_nearest_interactive_ancestor() {
        let mut engine = Engine::new(20);
        block(&mut engine, 2, ROOT, "one");
        block(&mut engine, 3, ROOT, "two");
        let property = StyleProperty::Interactive(true);
        engine.apply(Command::SetStyle { id: 3, property }).unwrap();
        engine.render(|_, _| ());

        assert_eq!(engine.node_at(1, 0), Some(3));
        assert_eq!(engine.node_at(0, 0), None);
    }

    #[test]
    fn node_at_finds_nothing_under_an_inert_node() {
        let mut engine = Engine::new(20);
        block(&mut engine, 2, ROOT, "outer");
        block(&mut engine, 3, 2, "inner");
        let property = StyleProperty::Interactive(true);
        engine.apply(Command::SetStyle { id: 3, property }).unwrap();
        engine.render(|_, _| ());
        assert_eq!(engine.node_at(1, 0), Some(3));

        let property = StyleProperty::Inert(true);
        engine.apply(Command::SetStyle { id: 2, property }).unwrap();
        engine.render(|_, _| ());
        assert_eq!(engine.node_at(1, 0), None);
    }

    #[test]
    fn node_at_leaves_out_the_margin() {
        let mut engine = Engine::new(20);
        block(&mut engine, 2, ROOT, "one");
        let commands = [
            StyleProperty::Interactive(true),
            StyleProperty::Margin(Side::Top, 1),
            StyleProperty::Margin(Side::Left, 2),
            StyleProperty::Margin(Side::Right, 3),
            StyleProperty::Padding(Side::Left, 1),
            StyleProperty::Width(Length::Cells(4)),
        ];
        for property in commands {
            engine.apply(Command::SetStyle { id: 2, property }).unwrap();
        }
        engine.render(|_, _| ());

        // The row above and the cells to either side are margin.
        assert_eq!(engine.node_at(0, 3), None);
        assert_eq!(engine.node_at(1, 0), None);
        assert_eq!(engine.node_at(1, 1), None);
        assert_eq!(engine.node_at(1, 7), None);
        // Padding and content are the node.
        assert_eq!(engine.node_at(1, 2), Some(2));
        assert_eq!(engine.node_at(1, 6), Some(2));
    }

    #[test]
    fn an_absolute_node_not_inserted_yet_is_left_out() {
        // A mount that fails halfway leaves its node created but never inserted.
        let mut engine = Engine::new(20);
        block(&mut engine, 2, ROOT, "one");
        engine
            .apply(Command::Create {
                id: 3,
                display: Display::Block,
            })
            .unwrap();
        let property = StyleProperty::Position(Position::Absolute);
        engine.apply(Command::SetStyle { id: 3, property }).unwrap();

        assert_eq!(patched_lines(&mut engine), 1);
        assert_eq!(engine.path_at(0, 0), vec![ROOT, 2, 1002]);
    }

    #[test]
    fn node_ids_can_be_reused_after_removal() {
        let mut engine = Engine::new(20);
        block(&mut engine, 2, ROOT, "one");
        engine.apply(Command::Remove { id: 2 }).unwrap();
        block(&mut engine, 2, ROOT, "two");

        assert_eq!(engine.tree().len(), 3);
    }
}
