use std::cell::RefCell;
use std::rc::Rc;

use crate::common;
use crate::tree::Tree;

use common::image::{image_measure_function, ImageContext};
use common::text::{text_measure_function, FontMetrics, TextContext, WritingMode, LOREM_IPSUM};
use mlua::prelude::*;
use taffy::{
    compute_block_layout, compute_cached_layout, compute_flexbox_layout, compute_grid_layout,
    compute_leaf_layout, compute_root_layout, prelude::*, round_layout, Cache, CacheTree,
};

#[derive(Debug, Copy, Clone)]
#[allow(dead_code)]
pub enum NodeKind {
    Flexbox,
    Grid,
    Block,
    Text,
    Image,
}

pub struct Node {
    pub kind: NodeKind,
    pub style: Style,
    pub text_data: Option<TextContext>,
    pub image_data: Option<ImageContext>,
    pub cache: Cache,
    pub unrounded_layout: Layout,
    pub final_layout: Layout,
    pub children: Vec<usize>,
}

#[derive(Clone)]
pub struct LuaNode {
    tree: Rc<RefCell<Tree>>,
    node_id: NodeId,
}

impl LuaNode {
    pub fn new(tree: Rc<RefCell<Tree>>, node_id: NodeId) -> Self {
        LuaNode { tree, node_id }
    }
}

impl LuaUserData for LuaNode {
    fn add_methods<M: LuaUserDataMethods<Self>>(methods: &mut M) {
        methods.add_method_mut("remove_child", |_, this, child_ud: LuaAnyUserData| {
            let child: LuaNode = child_ud.borrow::<LuaNode>()?.clone();
            let mut tree = this.tree.borrow_mut();
            tree.remove_child(this.node_id.into(), child.node_id.into());
            Ok(())
        });

        methods.add_method_mut("append_child", |_, this, child_ud: LuaAnyUserData| {
            let child: LuaNode = child_ud.borrow::<LuaNode>()?.clone();
            let mut tree = this.tree.borrow_mut();
            tree.append_child(this.node_id.into(), child.node_id.into());
            Ok(())
        });

        methods.add_method("contains", |_, this, child_ud: LuaAnyUserData| {
            let child: LuaNode = child_ud.borrow::<LuaNode>()?.clone();
            let tree = this.tree.borrow();
            Ok(tree.contains_child(this.node_id.into(), child.node_id.into()))
        });

        methods.add_method("has_child_nodes", |_, this, ()| {
            let tree = this.tree.borrow();
            Ok(tree.has_child_nodes(this.node_id.into()))
        });

        methods.add_meta_method(LuaMetaMethod::ToString, |_, this, ()| {
            let tree = this.tree.borrow();
            Ok(tree.to_string(this.node_id.into()))
        });
    }
}

impl Default for Node {
    fn default() -> Self {
        Node {
            kind: NodeKind::Flexbox,
            style: Style::default(),
            text_data: None,
            image_data: None,
            cache: Cache::new(),
            unrounded_layout: Layout::with_order(0),
            final_layout: Layout::with_order(0),
            children: Vec::new(),
        }
    }
}

#[allow(dead_code)]
impl Node {
    pub fn new_from_kind_str(kind_str: String, style: Style) -> Node {
        match kind_str.as_str() {
            "flexbox" => Node::new_column(style),
            "grid" => Node::new_grid(style),
            "block" => Node::new_block(style),
            // "text" => Node::new_text(TextContext {
            //     text_content: String::from("123"),
            //     writing_mode: WritingMode::Horizontal,
            // }),
            // "image" => Node::new_image(style, None),
            _ => Node::new_block(style),
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
            // style,
            text_data: Some(text_data),
            ..Node::default()
        }
    }
    pub fn new_image(style: Style, image_data: Option<ImageContext>) -> Node {
        Node {
            kind: NodeKind::Image,
            style,
            // image_data: Some(image_data),
            ..Node::default()
        }
    }
}
