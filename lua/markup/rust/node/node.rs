use std::cell::RefCell;
use std::rc::Rc;

use crate::{compute::TextContext, tree::Tree};

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
    Inline,
    Text,
}

// pub struct TextStyle {
//     pub highlight: &'static str,
// }
//
// impl Style for TextStyle {}

pub struct Node {
    pub kind: NodeKind,
    pub style: Style,
    pub text_data: Option<TextContext>,
    pub cache: Cache,
    pub unrounded_layout: Layout,
    pub final_layout: Layout,
    pub children: Vec<usize>,
}

#[derive(Clone)]
pub struct LuaNode {
    tree: Rc<RefCell<Tree>>,
    node_id: usize,
}

impl LuaNode {
    pub fn new(tree: Rc<RefCell<Tree>>, node_id: usize) -> Self {
        LuaNode { tree, node_id }
    }
}

impl LuaUserData for LuaNode {
    fn add_fields<F: LuaUserDataFields<Self>>(fields: &mut F) {
        // fields.add_meta_field("node_id", |_, this| Ok(this.node_id));
    }

    fn add_methods<M: LuaUserDataMethods<Self>>(methods: &mut M) {
        methods.add_method_mut("remove_child", |_, this, child_ud: LuaAnyUserData| {
            let child: LuaNode = child_ud.borrow::<LuaNode>()?.clone();
            let mut tree = this.tree.borrow_mut();
            tree.remove_child(this.node_id, child.node_id);
            Ok(())
        });

        methods.add_method_mut("append_child", |_, this, child_ud: LuaAnyUserData| {
            let child: LuaNode = child_ud.borrow::<LuaNode>()?.clone();
            let mut tree = this.tree.borrow_mut();
            tree.append_child(this.node_id, child.node_id);
            Ok(())
        });

        methods.add_method("contains", |_, this, child_ud: LuaAnyUserData| {
            let child: LuaNode = child_ud.borrow::<LuaNode>()?.clone();
            let tree = this.tree.borrow();
            Ok(tree.contains_child(this.node_id, child.node_id))
        });

        methods.add_method("has_child_nodes", |_, this, ()| {
            let tree = this.tree.borrow();
            Ok(tree.has_child_nodes(this.node_id))
        });

        methods.add_method_mut(
            "compute_layout",
            |_, this, (available_width, available_height): (LuaInteger, LuaInteger)| {
                let mut tree = this.tree.borrow_mut();

                tree.compute_layout(
                    this.node_id,
                    Size {
                        width: AvailableSpace::from(available_width as f32),
                        height: AvailableSpace::from(available_height as f32),
                    },
                    true,
                );

                Ok(())
            },
        );

        methods.add_method("layout", |_, this, ()| {
            let tree = this.tree.borrow();

            // tree.layout

            Ok(())
        });

        methods.add_meta_method(LuaMetaMethod::ToString, |_, this, ()| {
            let tree = this.tree.borrow();
            Ok(tree.to_string(this.node_id))
        });
    }
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
            "inline" => Node::new_inline(style),
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
