//! Moves a cursor between interactive nodes, for menus and lists of buttons.

use super::Engine;
use super::inspect::Rect;
use super::style::{Display, Position};
use super::tree::Index;

impl Engine {
    fn interactive_rects(&self, index: Index, x: i32, y: i32, rects: &mut Vec<Rect>) {
        let tree = self.tree();
        let node = tree.node(index);

        if node.display == Display::Contents {
            for &child in &node.children {
                self.interactive_rects(child, x, y, rects);
            }
            return;
        }

        let (x, y) = if node.style.position() == Position::Absolute {
            self.origin(index)
        } else {
            let (shift_x, shift_y) = node.style.relative_offset();
            (x + node.geometry.x + shift_x, y + node.geometry.y + shift_y)
        };

        if node.style.interactive {
            rects.push(Rect {
                x: x + node.style.margin.left,
                y: y + node.style.margin.top,
                width: node.geometry.content.width + node.style.padding.horizontal(),
                height: node.geometry.content.height + node.style.padding.vertical(),
            });
            return;
        }

        let content_x = x + node.style.margin.left + node.style.padding.left;
        let content_y = y + node.style.margin.top + node.style.padding.top;
        for &child in &node.children {
            self.interactive_rects(child, content_x, content_y, rects);
        }
    }

    /// Where a cursor that moved from `from` to `to` should land. Stays inside
    /// an interactive node, otherwise jumps to the nearest one in the direction
    /// of travel, and goes back when there is none. Positions are `(row, col)`.
    pub fn snap(&self, from: (i32, i32), to: (i32, i32)) -> Option<(i32, i32)> {
        let mut rects = Vec::new();
        self.interactive_rects(self.root_index(), 0, 0, &mut rects);
        if rects.is_empty() {
            return None;
        }

        let (row, col) = to;
        let contains = |rect: &Rect| {
            row >= rect.y && row < rect.y + rect.height && col >= rect.x && col < rect.x + rect.width
        };
        if rects.iter().any(contains) {
            return Some(to);
        }

        let ahead = |rect: &&Rect| match row.cmp(&from.0) {
            std::cmp::Ordering::Greater => rect.y + rect.height > row,
            std::cmp::Ordering::Less => rect.y <= row,
            std::cmp::Ordering::Equal => true,
        };

        // Rows cost twice as much as columns, since cells are twice as tall.
        let distance = |rect: &&Rect| {
            let dx = (rect.x - col).max(col - (rect.x + rect.width - 1)).max(0);
            let dy = (rect.y - row).max(row - (rect.y + rect.height - 1)).max(0);
            dy * 2 + dx
        };

        let target = rects.iter().filter(ahead).min_by_key(distance);
        Some(target.map_or(from, |rect| (rect.y, rect.x)))
    }
}

#[cfg(test)]
mod tests {
    use super::super::protocol::{Command, StyleProperty};
    use super::super::style::Display;
    use super::super::{Engine, ROOT};

    fn engine_with_buttons(rows: &[i32]) -> Engine {
        let mut engine = Engine::new(20);
        let mut id = 2;
        for row in 0..=*rows.iter().max().unwrap() {
            engine.apply(Command::Create { id, display: Display::Block }).unwrap();
            engine.apply(Command::CreateText { id: id + 1, text: "row".to_string(), width: 3 }).unwrap();
            engine.apply(Command::Insert { parent: id, child: id + 1, before: None }).unwrap();
            engine.apply(Command::Insert { parent: ROOT, child: id, before: None }).unwrap();
            if rows.contains(&row) {
                let property = StyleProperty::Interactive(true);
                engine.apply(Command::SetStyle { id, property }).unwrap();
            }
            id += 2;
        }
        engine.render(|_, _| ());
        engine
    }

    #[test]
    fn nothing_interactive_leaves_the_cursor_alone() {
        let engine = Engine::new(20);
        assert_eq!(engine.snap((0, 0), (1, 0)), None);
    }

    #[test]
    fn stays_inside_a_button() {
        let engine = engine_with_buttons(&[1, 3]);
        assert_eq!(engine.snap((1, 0), (3, 2)), Some((3, 2)));
    }

    #[test]
    fn jumps_over_gaps_in_the_direction_of_travel() {
        let engine = engine_with_buttons(&[1, 4]);
        assert_eq!(engine.snap((1, 0), (2, 0)), Some((4, 0)));
        assert_eq!(engine.snap((4, 0), (3, 0)), Some((1, 0)));
    }

    #[test]
    fn goes_back_when_nothing_is_ahead() {
        let engine = engine_with_buttons(&[1, 2, 5]);
        let mut engine = engine;
        engine.apply(Command::CreateText { id: 100, text: "tail".to_string(), width: 4 }).unwrap();
        engine.apply(Command::Insert { parent: ROOT, child: 100, before: None }).unwrap();
        engine.render(|_, _| ());

        assert_eq!(engine.snap((5, 0), (6, 0)), Some((5, 0)));
    }
}
