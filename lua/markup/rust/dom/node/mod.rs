mod lua;

use std::str::FromStr;

pub use lua::*;

use crate::prelude::*;
use mlua::prelude::*;
use taffy::{Cache, prelude::*};

#[derive(Debug, Copy, Clone)]
#[allow(dead_code)]
pub enum NodeKind {
    Flexbox,
    Grid,
    Block,
    Inline,
    Text,
}

#[derive(Debug, Clone)]
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

impl Default for Node {
    fn default() -> Self {
        Node {
            kind: NodeKind::Flexbox,
            style: Style::default(),
            text_data: None,
            cache: Cache::new(),
            unrounded_layout: Layout::with_order(0),
            final_layout: Layout::with_order(0),
            highlight: None,
            children: Vec::new(),
            computed_lines: None,
        }
    }
}

// impl FromStr for Node {
//     type Err;

//     fn from_str(s: &str) -> Result<Self, Self::Err> {
//         match s {
//             "flex" => Node::new_column(style),
//             "grid" => Node::new_grid(style),
//             "block" => Node::new_block(style),
//             "inline" => Node::new_inline(style),
//             _ => Node::new_block(style),
//         }
//     }
// }

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
        

        Ok(Node {
            ..Default::default()
        })
    }
}

#[allow(dead_code)]
impl Node {
    // pub fn new_from_kind_str(kind_str: String, style: Style) -> Node {
    //     match kind_str.as_str() {
    //         "flex" => Node::new_column(style),
    //         "grid" => Node::new_grid(style),
    //         "block" => Node::new_block(style),
    //         "inline" => Node::new_inline(style),
    //         _ => Node::new_block(style),
    //     }
    // }
    // pub fn new_from_kind(kind: NodeKind, style: Style) -> Node {
    //     match kind {
    //         NodeKind::Flexbox => Node::new_column(style),
    //         NodeKind::Grid => Node::new_grid(style),
    //         NodeKind::Block => Node::new_block(style),
    //         NodeKind::Inline => Node::new_inline(style),
    //         _ => panic!("Unsupported node kind: {:?}", kind),
    //     }
    // }
    // pub fn new_from_str(str: &str) -> Node {
    //     let chunks = str
    //         .split_whitespace()
    //         .into_iter()
    //         .map(|x| TextChunk {
    //             text_content: x.to_string(),
    //             display_width: x.len() as i32,
    //         })
    //         .collect::<Vec<TextChunk>>();
    //
    //     Node::new_text(TextContext {
    //         chunks,
    //         ..TextContext::default()
    //     })
    // }
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
