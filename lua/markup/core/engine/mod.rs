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
    /// Nodes laid out, not counting those that kept a cached layout.
    pub layouts: usize,
    pub layout: f64,
    pub paint: f64,
    pub diff: f64,
}

pub struct Engine {
    tree: Tree,
    root: Index,
    width: i32,
    lines: Vec<Line>,
    /// Painted layers from back to front, including the root for normal flow.
    layers: Vec<ClientId>,
    /// Whether a command came since the last frame. Without one the next is
    /// the same, so it is not laid out, painted or diffed at all.
    changed: bool,
}

/// Whether `new` breaks into lines as `old` does, given the same widths: every
/// character at the same byte, and of the same kind to line breaking, so the
/// pieces a wrap cut `old` into fit `new` as they are. The widths of what is
/// not ASCII come with `SetCells`, which lays out anew when they differ.
fn breaks_alike(old: &str, new: &str) -> bool {
    fn kind(character: char) -> u8 {
        match character {
            '\n' => 0,
            ' ' | '\t' => 1,
            '-' | '\u{2010}' | '\u{2013}' => 2,
            '0'..='9' => 3,
            _ if character.is_ascii() => 4,
            _ => 5,
        }
    }
    old.len() == new.len()
        && old.chars().count() == new.chars().count()
        && old
            .chars()
            .zip(new.chars())
            .all(|(a, b)| a.len_utf8() == b.len_utf8() && kind(a) == kind(b))
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
            layers: Vec::new(),
            changed: true,
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
        self.changed = true;
    }

    pub fn apply(&mut self, command: Command) -> Result<(), TreeError> {
        self.changed = true;
        let tree = &mut self.tree;
        match command {
            Command::Create { id, display } => {
                tree.create(id, display)?;
            }
            Command::CreateCanvas { id, display } => {
                let index = tree.create(id, display)?;
                tree.node_mut(index).canvas = Some(Box::default());
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
                // Wrapped text can break differently at the same total width,
                // unless each character is where it was and breaks as it did.
                let relayout = node.text_width != width
                    || (node.fragments.is_some() && !breaks_alike(&node.text, &text));
                // Text that is not ASCII comes with its cells next, which keep
                // what it was laid out with when they are the same.
                if text.is_ascii() {
                    node.cells = None;
                }
                node.text = text;
                node.text_width = width;
                if relayout {
                    tree.mark_dirty(index);
                }
            }
            Command::SetStyle { id, property } => {
                let index = tree.index_of(id)?;
                let inherited = matches!(property, StyleProperty::WhiteSpace(_));
                let paint_only = property.paint_only();
                property.apply(&mut tree.node_mut(index).style);
                tree.sync_position(index);
                if inherited {
                    tree.mark_subtree_dirty(index);
                } else if !paint_only {
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
                let node = tree.node_mut(index);
                // The same widths lay out the same, as `SetText` keeps a
                // layout for the same width: wrapped text too, as `SetText` has
                // laid out anew what no longer breaks the same way.
                let relayout = node.cells.as_deref() != Some(&cells[..]);
                node.cells = Some(cells.into_boxed_slice());
                if relayout {
                    tree.mark_dirty(index);
                }
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
            Command::SetCanvas { id, canvas } => {
                let index = tree.index_of(id)?;
                tree.node_mut(index).canvas = Some(Box::new(canvas));
            }
        }
        Ok(())
    }

    /// Runs layout, paint and diff, then hands the patches to `emit` before the
    /// new frame replaces the old one.
    pub fn render<T>(&mut self, emit: impl FnOnce(&[diff::Patch], Timings) -> T) -> T {
        let mut timings = Timings::default();
        if !self.changed {
            return emit(&[], timings);
        }
        self.changed = false;

        let started = Instant::now();
        self.tree.arranged = 0;
        let size = layout::measure(
            &mut self.tree,
            self.root,
            layout::Constraints::available(self.width),
        );
        layout::absolute::layout(&mut self.tree);
        let height =
            self.height_with_absolutes(size.height.max(self.overflow_bottom(self.root, 0)));
        timings.layout = elapsed_ms(started);
        timings.layouts = self.tree.arranged;

        let started = Instant::now();
        // A buffer always has a line, so a frame does too.
        let (lines, layers) = paint::paint(&self.tree, self.root, height.max(1));
        self.layers = layers;
        timings.paint = elapsed_ms(started);

        let started = Instant::now();
        let patches = diff::diff(&self.lines, &lines);
        timings.diff = elapsed_ms(started);

        let result = emit(&patches, timings);
        drop(patches);
        self.lines = lines;
        result
    }

    /// The lowest row anything in flow reaches, as the scrollable overflow of a
    /// CSS document: a box keeps its height, and what is taller than it still
    /// shows below it, unless a box around it cuts its rows off.
    fn overflow_bottom(&self, index: Index, y: i32) -> i32 {
        let node = self.tree.node(index);
        let style = &node.style;
        let mut bottom = y + node.geometry.outer.height;
        if style.extra().clip {
            return bottom;
        }
        let content_y = y + style.margin.top + style.inner().top;
        let mut stack: Vec<Index> = node.children.iter().rev().copied().collect();
        while let Some(child) = stack.pop() {
            let entry = self.tree.node(child);
            if entry.display == Display::Contents {
                stack.extend(entry.children.iter().rev());
                continue;
            }
            if entry.style.position() == Position::Absolute {
                continue;
            }
            let (_, shift_y) = entry.style.relative_offset();
            let child_y = content_y + entry.geometry.y + shift_y;
            bottom = bottom.max(self.overflow_bottom(child, child_y));
        }
        bottom
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
        self.tree.origin(index)
    }

    /// Finds the innermost interactive node on a cell. Nothing under an inert
    /// node counts.
    pub fn node_at(&self, row: i32, col: i32) -> Option<ClientId> {
        self.interactive_in(&self.path_at(row, col))
    }

    /// The innermost interactive node on a path from the root, short of
    /// anything inert.
    fn interactive_in(&self, path: &[ClientId]) -> Option<ClientId> {
        let mut found = None;
        for &id in path {
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
    /// boxes with non-negative `z` sit on top, highest `z` first. Negative `z`
    /// sits behind flow, and takes the cell when nothing in flow there takes
    /// presses. As HTML's `inert`, an inert box is not there to be found.
    pub fn path_at(&self, row: i32, col: i32) -> Vec<ClientId> {
        let tree = &self.tree;

        let mut flow = Vec::new();
        for &id in self.layers.iter().rev() {
            let Ok(index) = tree.index_of(id) else {
                continue;
            };
            if index == self.root {
                if self.descend(index, 0, 0, row, col, &mut flow)
                    && self.interactive_in(&flow).is_some()
                {
                    return flow;
                }
                continue;
            }
            let mut path = self.ancestors(index);
            if tree.node(index).style.extra().inert
                || path.iter().any(|&id| {
                    tree.index_of(id)
                        .is_ok_and(|ancestor| tree.node(ancestor).style.extra().inert)
                })
            {
                continue;
            }
            let (x, y) = self.origin(index);
            if self.descend(index, x, y, row, col, &mut path) {
                return path;
            }
        }
        flow
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
        let style = &node.style;
        let content_x = x + style.margin.left + style.inner().left;
        let content_y = y + style.margin.top + style.inner().top;

        if !inside {
            // An inline split around a block holds it outside its own pieces:
            // the cell can still be on what it holds.
            if node.fragments.is_none() {
                return false;
            }
            let at = path.len();
            path.push(node.client);
            let found = node
                .children
                .iter()
                .any(|&child| self.descend_child(child, content_x, content_y, row, col, path));
            if !found {
                path.truncate(at);
            }
            return found;
        }

        path.push(node.client);
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

    fn layouts(engine: &mut Engine) -> usize {
        engine.render(|_, timings| timings.layouts)
    }

    #[test]
    fn text_overflow_uses_measured_cells_and_changes_without_layout() {
        let lua = mlua::Lua::new();
        let mut engine = Engine::new(5);
        let mut apply = |source: &str| {
            let ops: mlua::Table = lua.load(source).eval().unwrap();
            protocol::decode(&lua, &ops, ops.raw_len(), |command| {
                engine.apply(command).unwrap();
                Ok(())
            })
            .unwrap();
            let arranged = layouts(&mut engine);
            (engine.lines[0].text.clone(), arranged)
        };

        let (text, arranged) = apply(
            r#"return {
                4, 1, 44, 1,
                4, 1, 46, 2,
                4, 1, 49, { "󰇘", 1, "1" },
                1, 2, 3,
                2, 3, "é界xyz", 6,
                10, 3, "02",
                5, 1, 2, 0,
                5, 2, 3, 0,
            }"#,
        );
        assert!(arranged > 0);
        assert_eq!(text, "é界x󰇘");
        assert_eq!(
            apply(r#"return { 4, 1, 49, { ">>", 2, "" } }"#),
            ("é界>>".into(), 0)
        );
        assert_eq!(apply("return { 4, 1, 49, false }"), ("é界xy".into(), 0));
        assert_eq!(apply("return { 8, 7 }").0, "é界xyz");
    }

    #[test]
    fn a_frame_without_commands_does_nothing() {
        let mut engine = Engine::new(20);
        engine
            .apply(Command::Create {
                id: 2,
                display: Display::Block,
            })
            .unwrap();
        engine
            .apply(Command::CreateText {
                id: 3,
                text: "words".into(),
                width: 5,
            })
            .unwrap();
        engine
            .apply(Command::Insert {
                parent: 2,
                child: 3,
                before: None,
            })
            .unwrap();
        engine
            .apply(Command::Insert {
                parent: ROOT,
                child: 2,
                before: None,
            })
            .unwrap();
        assert_eq!(engine.render(|patches, _| patches.len()), 1);

        // Nothing came, so nothing is laid out, painted or sent.
        let (patches, timings) = engine.render(|patches, timings| (patches.len(), timings));
        assert_eq!(patches, 0);
        assert_eq!((timings.layouts, timings.paint), (0, 0.0));
        assert_eq!(engine.lines[0].text, "words");

        // A command that changes nothing still gets a frame, which sends nothing.
        engine.apply(Command::Resize { width: 20 }).unwrap();
        assert_eq!(engine.render(|patches, _| patches.len()), 0);
        engine
            .apply(Command::SetText {
                id: 3,
                text: "other".into(),
                width: 5,
            })
            .unwrap();
        assert_eq!(engine.render(|patches, _| patches.len()), 1);
        assert_eq!(engine.lines[0].text, "other");
    }

    #[test]
    fn a_highlight_lays_nothing_out_again() {
        let mut engine = Engine::new(20);
        block(&mut engine, 2, ROOT, "one");
        assert!(layouts(&mut engine) > 0);

        let property = StyleProperty::Highlight(7);
        engine.apply(Command::SetStyle { id: 2, property }).unwrap();
        assert_eq!(layouts(&mut engine), 0);

        // What can move something still lays it out.
        let property = StyleProperty::Padding(Side::Left, 1);
        engine.apply(Command::SetStyle { id: 2, property }).unwrap();
        assert!(layouts(&mut engine) > 0);
    }

    #[test]
    fn text_with_the_same_cells_lays_nothing_out_again() {
        let mut engine = Engine::new(20);
        block(&mut engine, 2, ROOT, "x");
        let set = |engine: &mut Engine, text: &str, cells: Vec<u8>| {
            let width = cells.iter().map(|&cell| cell as i32).sum();
            let text = text.to_string();
            engine
                .apply(Command::SetText {
                    id: 1002,
                    text,
                    width,
                })
                .unwrap();
            engine.apply(Command::SetCells { id: 1002, cells }).unwrap();
        };
        set(&mut engine, "▁▂", vec![1, 1]);
        layouts(&mut engine);

        set(&mut engine, "▃▄", vec![1, 1]);
        assert_eq!(layouts(&mut engine), 0);

        // Other widths are laid out anew, even at the same total.
        set(&mut engine, "語", vec![2]);
        assert!(layouts(&mut engine) > 0);
    }

    #[test]
    fn wrapped_text_that_breaks_alike_lays_nothing_out_again() {
        let mut engine = Engine::new(6);
        block(&mut engine, 2, ROOT, "x");
        let set = |engine: &mut Engine, text: &str, cells: Vec<u8>| {
            let ascii = text.chars().filter(char::is_ascii).count() as i32;
            let width = ascii + cells.iter().map(|&cell| cell as i32).sum::<i32>();
            let text = text.to_string();
            engine
                .apply(Command::SetText {
                    id: 1002,
                    text,
                    width,
                })
                .unwrap();
            engine.apply(Command::SetCells { id: 1002, cells }).unwrap();
        };
        let lines = |engine: &Engine| -> Vec<String> {
            engine
                .lines
                .iter()
                .map(|line| line.text.trim_end().to_string())
                .collect()
        };
        set(&mut engine, "load ⠋ ok go", vec![1]);
        layouts(&mut engine);
        assert_eq!(lines(&engine), ["load ⠋", "ok go"]);

        // A spinner's next frame: each character where it was, as wide, and
        // breaking as it did, so the wrap stays and only its text is new.
        set(&mut engine, "load ⠙ ok go", vec![1]);
        assert_eq!(layouts(&mut engine), 0);
        assert_eq!(lines(&engine), ["load ⠙", "ok go"]);

        // A space somewhere else breaks elsewhere, and a character as long in
        // bytes but wider takes more room: each is laid out anew, and wraps
        // as a fresh engine given only that text does.
        for (text, cells) in [("lo ad⠹ okgo", vec![1]), ("lo ad語okgo", vec![2])] {
            set(&mut engine, text, cells.clone());
            assert!(layouts(&mut engine) > 0, "{text}");

            let mut fresh = Engine::new(6);
            block(&mut fresh, 2, ROOT, "x");
            set(&mut fresh, text, cells);
            layouts(&mut fresh);
            assert_eq!(lines(&engine), lines(&fresh), "{text}");
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

    #[test]
    fn canvas_surfaces_never_lay_out_and_decode_binary_ranges() {
        let lua = mlua::Lua::new();
        let mut engine = Engine::new(20);
        let num = mlua::Value::Integer;
        let text = |s: &str| mlua::Value::String(lua.create_string(s).unwrap());
        let pack = |ranges: &[(u32, u32, u32)]| {
            let mut bytes = Vec::with_capacity(ranges.len() * 12);
            for &(start, end, hl) in ranges {
                for value in [start, end, hl] {
                    bytes.extend_from_slice(&value.to_ne_bytes());
                }
            }
            mlua::Value::String(lua.create_string(&bytes).unwrap())
        };

        let apply_ops = |engine: &mut Engine, values: Vec<mlua::Value>| {
            let ops = lua.create_table().unwrap();
            for (i, v) in values.into_iter().enumerate() {
                ops.raw_set(i + 1, v).unwrap();
            }
            protocol::decode(&lua, &ops, ops.raw_len(), |command| {
                engine.apply(command).unwrap();
                Ok(())
            })
            .unwrap();
            layouts(engine)
        };

        // create block #2 two rows tall, insert into ROOT, set_canvas 6x2
        assert!(
            apply_ops(
                &mut engine,
                vec![
                    num(1),
                    num(2),
                    num(1),
                    num(4),
                    num(2),
                    num(10),
                    num(2),
                    num(5),
                    num(1),
                    num(2),
                    num(0),
                    num(12),
                    num(2),
                    num(6),
                    num(2),
                    num(2),
                    // One run from the left edge starts with its text.
                    text("abcd"),
                    num(-1),
                    text(""),
                    pack(&[(0, 2, 7), (2, 4, 8)]),
                    num(1),
                    num(0),
                    text("你x"),
                    num(3),
                    text("2"),
                    pack(&[(0, 2, 9), (2, 3, 10)]),
                ],
            ) > 0
        );
        assert_eq!(engine.describe(2).unwrap().display, "block");
        assert_eq!(engine.lines.len(), 2);
        assert_eq!(engine.lines[0].text, "abcd");
        assert_eq!(
            engine.lines[0].marks,
            vec![
                paint::Mark {
                    start: 0,
                    end: 2,
                    hl: 7
                },
                paint::Mark {
                    start: 2,
                    end: 4,
                    hl: 8
                },
            ]
        );
        assert_eq!(engine.lines[1].text, "你x");
        assert_eq!(
            engine.lines[1].marks,
            vec![
                paint::Mark {
                    start: 0,
                    end: 3,
                    hl: 9
                },
                paint::Mark {
                    start: 3,
                    end: 4,
                    hl: 10
                },
            ]
        );

        // Updating content at the same size causes zero layouts.
        assert_eq!(
            apply_ops(
                &mut engine,
                vec![
                    num(12),
                    num(2),
                    num(6),
                    num(2),
                    num(2),
                    num(1),
                    num(0),
                    text("WXYZ"),
                    num(-1),
                    text(""),
                    pack(&[(1, 3, 11)]),
                    // Two runs, with a gap between them.
                    num(2),
                    num(0),
                    text("o"),
                    num(-1),
                    text(""),
                    num(3),
                    text("k"),
                    num(-1),
                    text(""),
                    text(""),
                ],
            ),
            0
        );
        assert_eq!(engine.lines[0].text, "WXYZ");
        assert_eq!(
            engine.lines[0].marks,
            vec![paint::Mark {
                start: 1,
                end: 3,
                hl: 11
            }]
        );
        assert_eq!(engine.lines[1].text, "o  k");

        // The surface never sizes the node: a taller one lays nothing out, and
        // the box cuts it off.
        assert_eq!(
            apply_ops(
                &mut engine,
                vec![
                    num(12),
                    num(2),
                    num(6),
                    num(3),
                    num(3),
                    num(1),
                    num(0),
                    text("a"),
                    num(-1),
                    text(""),
                    text(""),
                    num(1),
                    num(0),
                    text("b"),
                    num(-1),
                    text(""),
                    text(""),
                    num(1),
                    num(0),
                    text("c"),
                    num(-1),
                    text(""),
                    text(""),
                ],
            ),
            0
        );
        let texts: Vec<&str> = engine.lines.iter().map(|line| line.text.as_str()).collect();
        assert_eq!(texts, vec!["a", "b"]);
    }
}
