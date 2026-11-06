//! Read only queries for devtools. Nothing in the render path uses this, and
//! everything is fetched on demand, so closed tools cost nothing.

use super::Engine;
use super::style::{Display, Edges, Length, Position};
use super::tree::{ClientId, Index, Size, TreeError};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Rect {
    pub x: i32,
    pub y: i32,
    pub width: i32,
    pub height: i32,
}

/// A snapshot of one node. Contents nodes have no box of their own.
#[derive(Debug, Clone, PartialEq)]
pub struct NodeInfo {
    pub id: ClientId,
    pub parent: Option<ClientId>,
    pub display: &'static str,
    pub text: Option<String>,
    pub children: usize,
    pub rect: Option<Rect>,
    pub content: Size,
    pub margin: Edges,
    pub padding: Edges,
    pub width: String,
    pub height: String,
    pub spacing: i32,
    pub reverse: bool,
    pub hl: u32,
    pub interactive: bool,
    pub dirty: bool,
    pub position: &'static str,
}

fn display_name(display: Display) -> &'static str {
    match display {
        Display::Block => "block",
        Display::Inline => "inline",
        Display::Text => "text",
        Display::Flex => "flex",
        Display::Grid => "grid",
        Display::Contents => "contents",
    }
}

fn length_name(length: Length) -> String {
    match length {
        Length::Auto => "auto".to_string(),
        Length::Fit => "fit".to_string(),
        Length::Full => "full".to_string(),
        Length::Cells(cells) => cells.to_string(),
        Length::Fraction(share) => format!("{}%", (share * 100.0).round()),
    }
}

impl Engine {
    fn info(&self, index: Index) -> NodeInfo {
        let tree = self.tree();
        let node = tree.node(index);
        let style = &node.style;

        let rect = (node.display != Display::Contents).then(|| {
            let (x, y) = self.origin(index);
            Rect {
                x,
                y,
                width: node.geometry.outer.width,
                height: node.geometry.outer.height,
            }
        });

        NodeInfo {
            id: node.client,
            parent: node.parent.map(|parent| tree.node(parent).client),
            display: display_name(node.display),
            text: (node.display == Display::Text).then(|| node.text.clone()),
            children: node.children.len(),
            rect,
            content: node.geometry.content,
            margin: style.margin,
            padding: style.padding,
            width: length_name(style.width),
            height: length_name(style.height),
            spacing: style.spacing,
            reverse: style.reverse,
            hl: style.hl,
            interactive: style.interactive,
            dirty: node.dirty,
            position: match style.extra().position {
                Position::Static => "static",
                Position::Relative => "relative",
                Position::Absolute => "absolute",
            },
        }
    }

    pub fn describe(&self, id: ClientId) -> Result<NodeInfo, TreeError> {
        Ok(self.info(self.tree().index_of(id)?))
    }

    /// Children of a node. With `flatten`, groups are replaced by what they
    /// contain, which is the list layout actually sees.
    fn listing(&self, index: Index, flatten: bool) -> Vec<Index> {
        let tree = self.tree();
        if !flatten {
            return tree.node(index).children.clone();
        }

        let mut list = Vec::new();
        let mut stack: Vec<Index> = tree.node(index).children.iter().rev().copied().collect();
        while let Some(child) = stack.pop() {
            let node = tree.node(child);
            if node.display == Display::Contents {
                stack.extend(node.children.iter().rev());
            } else {
                list.push(child);
            }
        }
        list
    }

    /// A page of a node's children, with the total so huge lists stay cheap.
    pub fn children_of(
        &self,
        id: ClientId,
        offset: usize,
        limit: usize,
        flatten: bool,
    ) -> Result<(usize, Vec<NodeInfo>), TreeError> {
        let list = self.listing(self.tree().index_of(id)?, flatten);
        let page = list.iter().skip(offset).take(limit);
        Ok((list.len(), page.map(|&child| self.info(child)).collect()))
    }

    /// Position of a node in its parent's listing. With `flatten` the parent
    /// is the nearest ancestor that is not a group.
    pub fn child_position(&self, id: ClientId, flatten: bool) -> Result<Option<usize>, TreeError> {
        let tree = self.tree();
        let index = tree.index_of(id)?;

        let mut parent = tree.node(index).parent;
        if flatten {
            while let Some(ancestor) = parent {
                if tree.node(ancestor).display != Display::Contents {
                    break;
                }
                parent = tree.node(ancestor).parent;
            }
        }

        Ok(parent.and_then(|parent| {
            self.listing(parent, flatten).iter().position(|&child| child == index)
        }))
    }
}

#[cfg(test)]
mod tests {
    use super::super::protocol::{Command, StyleProperty};
    use super::super::style::Display;
    use super::super::{Engine, ROOT};
    use super::*;

    fn block(engine: &mut Engine, id: u32, parent: u32) {
        engine.apply(Command::Create { id, display: Display::Block }).unwrap();
        engine.apply(Command::Insert { parent, child: id, before: None }).unwrap();
    }

    fn text(engine: &mut Engine, id: u32, parent: u32, value: &str) {
        let text = value.to_string();
        let width = value.len() as i32;
        engine.apply(Command::CreateText { id, text, width }).unwrap();
        engine.apply(Command::Insert { parent, child: id, before: None }).unwrap();
    }

    #[test]
    fn rects_are_absolute_through_margins_and_groups() {
        let mut engine = Engine::new(20);
        text(&mut engine, 2, ROOT, "first");
        block(&mut engine, 3, ROOT);
        let property = StyleProperty::Margin(super::super::protocol::Side::Left, 4);
        engine.apply(Command::SetStyle { id: 3, property }).unwrap();
        engine.apply(Command::Create { id: 4, display: Display::Contents }).unwrap();
        engine.apply(Command::Insert { parent: 3, child: 4, before: None }).unwrap();
        text(&mut engine, 5, 4, "inner");
        engine.render(|_, _| ());

        let rect = engine.describe(5).unwrap().rect.unwrap();

        assert_eq!(rect, Rect { x: 4, y: 1, width: 5, height: 1 });
        assert_eq!(engine.describe(4).unwrap().rect, None);
    }

    #[test]
    fn children_are_paged() {
        let mut engine = Engine::new(20);
        for id in 2..12 {
            block(&mut engine, id, ROOT);
        }

        let (total, page) = engine.children_of(ROOT, 3, 2, false).unwrap();

        assert_eq!(total, 10);
        assert_eq!(page.iter().map(|info| info.id).collect::<Vec<_>>(), vec![5, 6]);
        assert_eq!(engine.child_position(5, false).unwrap(), Some(3));
    }

    #[test]
    fn flattening_pages_across_nested_groups() {
        let mut engine = Engine::new(20);
        let mut parent = ROOT;
        for id in 2..6 {
            engine.apply(Command::Create { id, display: Display::Contents }).unwrap();
            engine.apply(Command::Insert { parent, child: id, before: None }).unwrap();
            block(&mut engine, id + 100, id);
            parent = id;
        }

        let (total, page) = engine.children_of(ROOT, 1, 2, true).unwrap();

        assert_eq!(total, 4);
        assert_eq!(page.iter().map(|info| info.id).collect::<Vec<_>>(), vec![103, 104]);
        assert_eq!(engine.child_position(105, true).unwrap(), Some(3));
    }

    #[test]
    fn path_at_includes_groups_on_the_way_down() {
        let mut engine = Engine::new(20);
        engine.apply(Command::Create { id: 2, display: Display::Contents }).unwrap();
        engine.apply(Command::Insert { parent: ROOT, child: 2, before: None }).unwrap();
        block(&mut engine, 3, 2);
        text(&mut engine, 4, 3, "hello");
        engine.render(|_, _| ());

        assert_eq!(engine.path_at(0, 1), vec![ROOT, 2, 3, 4]);
    }

    #[test]
    fn absolute_nodes_report_their_real_place_and_win_hit_tests() {
        let mut engine = Engine::new(20);
        block(&mut engine, 2, ROOT);
        text(&mut engine, 3, 2, "flow");
        block(&mut engine, 4, ROOT);
        text(&mut engine, 5, 4, "top");
        for property in [
            StyleProperty::Position(crate::engine::style::Position::Absolute),
            StyleProperty::Left(Some(1)),
            StyleProperty::Top(Some(0)),
        ] {
            engine.apply(Command::SetStyle { id: 4, property }).unwrap();
        }
        engine.render(|_, _| ());

        let rect = engine.describe(4).unwrap().rect.unwrap();

        assert_eq!((rect.x, rect.y, rect.width), (1, 0, 3));
        assert_eq!(engine.path_at(0, 2), vec![ROOT, 4, 5]);
        assert_eq!(engine.path_at(0, 0), vec![ROOT, 2, 3]);
    }

    #[test]
    fn describe_reports_unknown_nodes() {
        let engine = Engine::new(20);
        assert_eq!(engine.describe(9).unwrap_err(), TreeError::UnknownNode(9));
    }
}
