//! Moves a cursor between interactive nodes, for menus and lists of buttons.

use super::Engine;
use super::inspect::Rect;
use super::style::{Display, Position};
use super::tree::Index;

impl Engine {
    /// Interactive nodes, each with the row a cursor lands on when entering it:
    /// its first row of content, rather than a border or padding above it.
    fn interactive_rects(&self, index: Index, x: i32, y: i32, rects: &mut Vec<Rect>, lands: &mut Vec<i32>) {
        let tree = self.tree();
        let node = tree.node(index);

        if node.display == Display::Contents {
            for &child in &node.children {
                self.interactive_rects(child, x, y, rects, lands);
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
            let rect = Rect {
                x: x + node.style.margin.left,
                y: y + node.style.margin.top,
                width: node.geometry.content.width + node.style.inner().horizontal(),
                height: node.geometry.content.height + node.style.inner().vertical(),
            };
            lands.push((rect.y + node.style.inner().top).min(rect.y + rect.height - 1));
            rects.push(rect);
            return;
        }

        let content_x = x + node.style.margin.left + node.style.inner().left;
        let content_y = y + node.style.margin.top + node.style.inner().top;
        for &child in &node.children {
            self.interactive_rects(child, content_x, content_y, rects, lands);
        }
    }

    /// Where a cursor that moved from `from` to `to` should land. Stays inside
    /// an interactive node, otherwise jumps to the nearest one in the direction
    /// of travel, and goes back when there is none. One press always reaches the
    /// next node, in any direction, since moving inside one shows nothing.
    /// Positions are `(row, col)`.
    ///
    /// With `text`, text counts as well. The column then survives the jump, and
    /// with nothing ahead the nearest text wins, so that `gg` still gets there.
    pub fn snap(&self, from: (i32, i32), to: (i32, i32), text: bool) -> Option<(i32, i32)> {
        let mut rects = Vec::new();
        let mut lands = Vec::new();
        self.interactive_rects(self.root_index(), 0, 0, &mut rects, &mut lands);
        if text {
            self.text_rects(&mut rects, &mut lands);
        }
        if rects.is_empty() {
            return None;
        }

        let (row, col) = to;
        let contains = |rect: &Rect| {
            row >= rect.y && row < rect.y + rect.height && col >= rect.x && col < rect.x + rect.width
        };
        let holds_from = |rect: &&Rect| {
            from.0 >= rect.y
                && from.0 < rect.y + rect.height
                && from.1 >= rect.x
                && from.1 < rect.x + rect.width
        };
        // The node the cursor is leaving, as text is free to move within.
        let own = if text { None } else { rects.iter().find(holds_from) };
        let moved = to != from;

        if let Some(rect) = rects.iter().find(|rect| contains(rect)) {
            let inside_own = own.is_some_and(|own| std::ptr::eq(own, rect));
            if !(moved && inside_own) {
                // A button is entered at its top, whichever side it is reached from.
                let land = lands[rects.iter().position(|other| std::ptr::eq(other, rect)).unwrap_or(0)];
                return Some(if text { to } else { (land, col) });
            }
        }

        let on_row = |rect: &Rect| row >= rect.y && row < rect.y + rect.height;
        let ahead = |rect: &&Rect| match (row.cmp(&from.0), own) {
            (std::cmp::Ordering::Greater, Some(_)) => rect.y > from.0 && !holds_from(rect),
            (std::cmp::Ordering::Less, Some(own)) => rect.y + rect.height <= own.y,
            (std::cmp::Ordering::Greater, None) => rect.y + rect.height > row,
            (std::cmp::Ordering::Less, None) => rect.y <= row,
            (std::cmp::Ordering::Equal, Some(own)) if col > from.1 => rect.x >= own.x + own.width,
            (std::cmp::Ordering::Equal, Some(own)) => rect.x + rect.width <= own.x,
            (std::cmp::Ordering::Equal, None) if !text => true,
            // Sideways it has to go past the gap, or it could never leave a span.
            (std::cmp::Ordering::Equal, None) if col > from.1 => on_row(rect) && rect.x > col,
            (std::cmp::Ordering::Equal, None) => on_row(rect) && rect.x + rect.width <= col,
        };

        let gaps = |rect: &Rect| {
            let dx = (rect.x - col).max(col - (rect.x + rect.width - 1)).max(0);
            let dy = (rect.y - row).max(row - (rect.y + rect.height - 1)).max(0);
            (dy, dx)
        };

        let target = if text {
            // The next line comes first, however far its text is from the column.
            let nearest = |rect: &&Rect| gaps(rect);
            rects.iter().filter(ahead).min_by_key(nearest).or_else(|| rects.iter().min_by_key(nearest))
        } else {
            // Rows cost twice as much as columns, since cells are twice as tall.
            let distance = |rect: &&Rect| {
                let (dy, dx) = gaps(rect);
                dy * 2 + dx
            };
            rects.iter().filter(ahead).min_by_key(distance)
        };

        Some(target.map_or(from, |rect| {
            if text {
                let last_row = rect.y + rect.height - 1;
                let last_col = rect.x + rect.width - 1;
                (row.clamp(rect.y, last_row), col.clamp(rect.x, last_col))
            } else {
                let index = rects.iter().position(|other| std::ptr::eq(other, rect)).unwrap_or(0);
                (lands[index], rect.x)
            }
        }))
    }

    fn text_rects(&self, rects: &mut Vec<Rect>, lands: &mut Vec<i32>) {
        for (y, line) in self.lines.iter().enumerate() {
            for &(start, end) in &line.spans {
                rects.push(Rect { x: start, y: y as i32, width: end - start, height: 1 });
                lands.push(y as i32);
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::super::protocol::{Command, Side, StyleProperty};
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
        assert_eq!(engine.snap((0, 0), (1, 0), false), None);
    }

    #[test]
    fn stays_inside_a_button() {
        let engine = engine_with_buttons(&[1, 3]);
        assert_eq!(engine.snap((1, 0), (3, 2), false), Some((3, 2)));
    }

    #[test]
    fn jumps_over_gaps_in_the_direction_of_travel() {
        let engine = engine_with_buttons(&[1, 4]);
        assert_eq!(engine.snap((1, 0), (2, 0), false), Some((4, 0)));
        assert_eq!(engine.snap((4, 0), (3, 0), false), Some((1, 0)));
    }

    /// Buttons two rows tall, one after the other.
    fn engine_with_tall_buttons(count: i32) -> Engine {
        let mut engine = Engine::new(20);
        let mut id = 2;
        for _ in 0..count {
            let button = id;
            engine.apply(Command::Create { id: button, display: Display::Block }).unwrap();
            engine.apply(Command::Insert { parent: ROOT, child: button, before: None }).unwrap();
            let property = StyleProperty::Interactive(true);
            engine.apply(Command::SetStyle { id: button, property }).unwrap();

            for _ in 0..2 {
                engine.apply(Command::Create { id: id + 1, display: Display::Block }).unwrap();
                engine.apply(Command::CreateText { id: id + 2, text: "row".to_string(), width: 3 }).unwrap();
                engine.apply(Command::Insert { parent: id + 1, child: id + 2, before: None }).unwrap();
                engine.apply(Command::Insert { parent: button, child: id + 1, before: None }).unwrap();
                id += 2;
            }
            id += 1;
        }
        engine.render(|_, _| ());
        engine
    }

    #[test]
    fn one_press_leaves_a_tall_button() {
        let engine = engine_with_tall_buttons(3);

        assert_eq!(engine.snap((0, 0), (1, 0), false), Some((2, 0)));
        assert_eq!(engine.snap((2, 0), (3, 0), false), Some((4, 0)));
        assert_eq!(engine.snap((4, 0), (3, 0), false), Some((2, 0)));
    }

    #[test]
    fn a_tall_button_keeps_the_cursor_at_the_ends() {
        let engine = engine_with_tall_buttons(2);

        assert_eq!(engine.snap((2, 0), (3, 0), false), Some((2, 0)));
    }

    /// Buttons in a row, with a blank column between them.
    fn engine_with_row() -> Engine {
        let mut engine = Engine::new(20);
        engine.apply(Command::Create { id: 2, display: Display::Flex }).unwrap();
        engine.apply(Command::Insert { parent: ROOT, child: 2, before: None }).unwrap();

        for (index, text) in ["aaaa", " ", "bbbb", " ", "cccc"].iter().enumerate() {
            let id = 3 + index as u32 * 2;
            engine.apply(Command::Create { id, display: Display::Block }).unwrap();
            let width = text.len() as i32;
            engine.apply(Command::CreateText { id: id + 1, text: text.to_string(), width }).unwrap();
            engine.apply(Command::Insert { parent: id, child: id + 1, before: None }).unwrap();
            engine.apply(Command::Insert { parent: 2, child: id, before: None }).unwrap();
            if text.trim().len() > 0 {
                let property = StyleProperty::Interactive(true);
                engine.apply(Command::SetStyle { id, property }).unwrap();
            }
        }
        engine.render(|_, _| ());
        engine
    }

    #[test]
    fn one_press_reaches_the_next_button_sideways() {
        let engine = engine_with_row();

        assert_eq!(engine.snap((0, 0), (0, 1), false), Some((0, 5)));
        assert_eq!(engine.snap((0, 5), (0, 6), false), Some((0, 10)));
        assert_eq!(engine.snap((0, 10), (0, 9), false), Some((0, 5)));
        assert_eq!(engine.snap((0, 5), (0, 4), false), Some((0, 0)));
    }

    #[test]
    fn sideways_stops_at_the_last_button() {
        let engine = engine_with_row();

        assert_eq!(engine.snap((0, 10), (0, 11), false), Some((0, 10)));
        assert_eq!(engine.snap((0, 0), (0, 0), false), Some((0, 0)));
    }

    #[test]
    fn a_big_jump_lands_where_it_was_aimed() {
        let engine = engine_with_row();

        // Such as `$`.
        assert_eq!(engine.snap((0, 0), (0, 12), false), Some((0, 12)));
    }

    #[test]
    fn sideways_finds_buttons_on_other_rows() {
        let engine = engine_with_tall_buttons(1);

        assert_eq!(engine.snap((0, 0), (0, 1), false), Some((0, 0)));
    }

    #[test]
    fn buttons_are_entered_below_their_border() {
        let mut engine = Engine::new(20);
        for id in [2, 4] {
            engine.apply(Command::Create { id, display: Display::Block }).unwrap();
            engine.apply(Command::CreateText { id: id + 1, text: "tile".to_string(), width: 4 }).unwrap();
            engine.apply(Command::Insert { parent: id, child: id + 1, before: None }).unwrap();
            engine.apply(Command::Insert { parent: ROOT, child: id, before: None }).unwrap();
            let property = StyleProperty::Interactive(true);
            engine.apply(Command::SetStyle { id, property }).unwrap();
            let property = StyleProperty::Padding(Side::Top, 1);
            engine.apply(Command::SetStyle { id, property }).unwrap();
        }
        engine.render(|_, _| ());

        // Each is two rows: its padding, then its text.
        assert_eq!(engine.snap((1, 0), (2, 0), false), Some((3, 0)));
        assert_eq!(engine.snap((3, 0), (2, 0), false), Some((1, 0)));
    }

    /// Rows of text at the given cells, with blank rows where there is none.
    fn engine_with_text(rows: &[Option<(i32, &str)>]) -> Engine {
        let mut engine = Engine::new(40);
        let mut id = 2;
        for row in rows {
            engine.apply(Command::Create { id, display: Display::Block }).unwrap();
            let (indent, text) = row.unwrap_or((0, " "));
            let value = format!("{}{text}", " ".repeat(indent as usize));
            let width = value.len() as i32;
            engine.apply(Command::CreateText { id: id + 1, text: value, width }).unwrap();
            engine.apply(Command::Insert { parent: id, child: id + 1, before: None }).unwrap();
            engine.apply(Command::Insert { parent: ROOT, child: id, before: None }).unwrap();
            id += 2;
        }
        engine.render(|_, _| ());
        engine
    }

    #[test]
    fn text_is_a_place_to_land() {
        let engine = engine_with_text(&[Some((2, "first")), None, None, Some((2, "second"))]);

        assert_eq!(engine.snap((0, 3), (1, 3), true), Some((3, 3)));
        assert_eq!(engine.snap((3, 3), (2, 3), true), Some((0, 3)));
    }

    #[test]
    fn padding_is_not_a_place_to_land() {
        let engine = engine_with_text(&[Some((2, "text"))]);

        assert_eq!(engine.snap((0, 2), (0, 1), true), Some((0, 2)));
        assert_eq!(engine.snap((0, 5), (0, 6), true), Some((0, 5)));
    }

    #[test]
    fn the_next_line_wins_over_one_closer_to_the_column() {
        let engine = engine_with_text(&[Some((10, "long")), None, Some((0, "a")), Some((10, "long"))]);

        assert_eq!(engine.snap((0, 11), (1, 11), true), Some((2, 0)));
    }

    #[test]
    fn with_nothing_ahead_the_nearest_text_wins() {
        let engine = engine_with_text(&[None, None, Some((2, "text")), None]);

        // `gg` and `G`.
        assert_eq!(engine.snap((2, 3), (0, 3), true), Some((2, 3)));
        assert_eq!(engine.snap((2, 3), (3, 3), true), Some((2, 3)));
    }

    #[test]
    fn nothing_on_screen_leaves_the_cursor_alone_in_text_mode() {
        let engine = Engine::new(20);
        assert_eq!(engine.snap((0, 0), (1, 0), true), None);
    }

    #[test]
    fn goes_back_when_nothing_is_ahead() {
        let engine = engine_with_buttons(&[1, 2, 5]);
        let mut engine = engine;
        engine.apply(Command::CreateText { id: 100, text: "tail".to_string(), width: 4 }).unwrap();
        engine.apply(Command::Insert { parent: ROOT, child: 100, before: None }).unwrap();
        engine.render(|_, _| ());

        assert_eq!(engine.snap((5, 0), (6, 0), false), Some((5, 0)));
    }
}
