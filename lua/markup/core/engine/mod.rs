//! The engine applies commands to the tree and reports what changed on screen.

pub mod diff;
pub mod layout;
pub mod lua;
pub mod paint;
pub mod protocol;
pub mod style;
pub mod tree;

use paint::Line;
use protocol::Command;
use std::time::Instant;
use style::Display;
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
                let resized = node.text_width != width;
                node.text = text;
                node.text_width = width;
                if resized {
                    tree.mark_dirty(index);
                }
            }
            Command::SetStyle { id, property } => {
                let index = tree.index_of(id)?;
                property.apply(&mut tree.node_mut(index).style);
                tree.mark_dirty(index);
            }
            Command::Insert { parent, child, before } => {
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
        }
        Ok(())
    }

    /// Runs layout, paint and diff, then hands the patches to `emit` before the
    /// new frame replaces the old one.
    pub fn render<T>(&mut self, emit: impl FnOnce(&[diff::Patch], Timings) -> T) -> T {
        let mut timings = Timings::default();

        let started = Instant::now();
        let size = layout::measure(&mut self.tree, self.root, self.width);
        timings.layout = elapsed_ms(started);

        let started = Instant::now();
        // A buffer always has a line, so a frame does too.
        let lines = paint::paint(&self.tree, self.root, size.height.max(1));
        timings.paint = elapsed_ms(started);

        let started = Instant::now();
        let patches = diff::diff(&self.lines, &lines);
        timings.diff = elapsed_ms(started);

        let result = emit(&patches, timings);
        drop(patches);
        self.lines = lines;
        result
    }

    /// Finds the innermost interactive node on a cell.
    pub fn node_at(&self, row: i32, col: i32) -> Option<ClientId> {
        self.find_at(self.root, 0, 0, row, col, None)
    }

    fn find_at(
        &self,
        index: Index,
        x: i32,
        y: i32,
        row: i32,
        col: i32,
        best: Option<ClientId>,
    ) -> Option<ClientId> {
        let node = self.tree.node(index);

        if node.display == Display::Contents {
            return node
                .children
                .iter()
                .find_map(|&child| self.find_at(child, x, y, row, col, None))
                .or(best);
        }

        let geometry = &node.geometry;
        let (x, y) = (x + geometry.x, y + geometry.y);
        let inside = row >= y
            && row < y + geometry.outer.height
            && col >= x
            && col < x + geometry.outer.width.max(1);
        if !inside {
            return None;
        }

        let best = if node.style.interactive { Some(node.client) } else { best };
        let style = &node.style;
        let content_x = x + style.margin.left + style.padding.left;
        let content_y = y + style.margin.top + style.padding.top;

        node.children
            .iter()
            .find_map(|&child| self.find_at(child, content_x, content_y, row, col, None))
            .or(best)
    }
}

#[cfg(test)]
mod tests {
    use super::protocol::{Command, StyleProperty};
    use super::style::Display;
    use super::*;

    fn block(engine: &mut Engine, id: u32, parent: u32, label: &str) {
        let commands = [
            Command::Create { id, display: Display::Block },
            Command::CreateText { id: id + 1000, text: label.to_string(), width: label.len() as i32 },
            Command::Insert { parent: id, child: id + 1000, before: None },
            Command::Insert { parent, child: id, before: None },
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
        engine.apply(Command::SetText { id: 1002, text, width: 3 }).unwrap();
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
            patches.iter().map(|p| (p.first, p.last, p.lines.len())).collect::<Vec<_>>()
        });

        assert_eq!(lines, vec![(0, 1, 1)]);
    }

    #[test]
    fn unknown_nodes_are_errors_not_panics() {
        let mut engine = Engine::new(20);
        assert_eq!(engine.apply(Command::Remove { id: 42 }), Err(TreeError::UnknownNode(42)));
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
    fn node_ids_can_be_reused_after_removal() {
        let mut engine = Engine::new(20);
        block(&mut engine, 2, ROOT, "one");
        engine.apply(Command::Remove { id: 2 }).unwrap();
        block(&mut engine, 2, ROOT, "two");

        assert_eq!(engine.tree().len(), 3);
    }
}
