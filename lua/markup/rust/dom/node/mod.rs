mod lua;

pub use lua::*;

use crate::prelude::*;
use mlua::prelude::*;
use std::str::FromStr;
use taffy::{Cache, prelude::*};

#[derive(Debug, Copy, Clone, Default)]
#[allow(dead_code)]
pub enum NodeKind {
    Flexbox,
    Grid,
    #[default]
    Block,
    Inline,
    Text,
}

#[derive(Debug, Clone, Default)]
pub struct Node {
    pub kind: NodeKind,
    pub style: Style,
    pub text_data: Option<TextContext>,
    pub highlight: Option<String>,
    pub cache: Cache,
    pub unrounded_layout: Layout,
    pub computed_lines: Option<Vec<ComputedLine>>,
    pub final_layout: Layout,
    pub children: Vec<usize>,
}

impl FromStr for Node {
    type Err = mlua::Error;

    fn from_str(s: &str) -> Result<Self, Self::Err> {
        let kind = NodeKind::from_str(s)?;
        Ok(Node {
            kind,
            ..Node::default()
        })
    }
}

impl FromStr for NodeKind {
    type Err = mlua::Error;

    fn from_str(s: &str) -> Result<Self, Self::Err> {
        match s {
            "flex" => Ok(NodeKind::Flexbox),
            "grid" => Ok(NodeKind::Grid),
            "block" => Ok(NodeKind::Block),
            "inline" => Ok(NodeKind::Inline),
            "text" => Ok(NodeKind::Text),
            _ => Ok(NodeKind::Block),
        }
    }
}

impl TryFrom<ElementKind> for NodeKind {
    type Error = mlua::Error;

    fn try_from(kind: ElementKind) -> Result<Self, Self::Error> {
        match kind {
            ElementKind::Element(str) => Ok(NodeKind::from_str(str.as_str())?),
            ElementKind::Text => Ok(NodeKind::Text),
            _ => Err(mlua::Error::external(format!(
                "Unsupported NodeKind: {:?}",
                kind
            ))),
        }
    }
}

impl TryFrom<Element> for Node {
    type Error = mlua::Error;

    fn try_from(element: Element) -> Result<Self, Self::Error> {
        let kind = NodeKind::try_from(element.kind)?;
        let style = Style::try_from(element.props)?;

        Ok(Node {
            kind,
            style,
            ..Default::default()
        })
    }
}

#[allow(dead_code)]
impl Node {
    pub fn new(kind: NodeKind, style: Option<Style>) -> Node {
        Node {
            kind,
            style: style.unwrap_or_default(),
            ..Node::default()
        }
    }

    pub fn new_row(style: Style) -> Node {
        Node {
            kind: NodeKind::Flexbox,
            style: Style {
                display: Display::Flex,
                flex_direction: FlexDirection::Row,
                ..style
            },
            ..Node::default()
        }
    }
    pub fn new_column(style: Style) -> Node {
        Node {
            kind: NodeKind::Flexbox,
            style: Style {
                display: Display::Flex,
                flex_direction: FlexDirection::Column,
                ..style
            },
            ..Node::default()
        }
    }
    pub fn new_block(style: Style) -> Node {
        Node {
            kind: NodeKind::Block,
            style: Style {
                display: Display::Block,
                ..style
            },
            ..Node::default()
        }
    }
    pub fn new_inline(style: Style) -> Node {
        Node {
            kind: NodeKind::Inline,
            style: Style { ..style },
            ..Node::default()
        }
    }
    pub fn new_grid(style: Style) -> Node {
        Node {
            kind: NodeKind::Grid,
            style: Style {
                display: Display::Grid,
                ..style
            },
            ..Node::default()
        }
    }
    pub fn new_text(text_data: TextContext) -> Node {
        Node {
            kind: NodeKind::Text,
            text_data: Some(text_data),
            ..Node::default()
        }
    }
}
