use std::cell::RefCell;
use std::rc::Rc;

use crate::compute::{compute_text_layout, LayoutTextContainer, TextContext, WritingMode};
use crate::node::{node, LuaNode, LuaProps, Node, NodeKind};
use crate::tree::print::print_tree_to_string;

use mlua::prelude::*;
use taffy::util::print_tree;
use taffy::{
    compute_block_layout, compute_cached_layout, compute_flexbox_layout, compute_grid_layout,
    compute_leaf_layout, compute_root_layout, prelude::*, round_layout, Cache, CacheTree,
};

#[derive(Default)]
pub struct Tree {
    pub(super) nodes: Vec<Node>,
}

impl Tree {
    pub fn new() -> Tree {
        Tree { nodes: Vec::new() }
    }

    pub fn add_node(&mut self, node: Node) -> usize {
        self.nodes.push(node);
        self.nodes.len() - 1
    }

    pub fn append_child(&mut self, parent: usize, child: usize) {
        self.nodes[parent].children.push(child);
    }

    pub fn remove_child(&mut self, parent: usize, child: usize) -> bool {
        if let Some(pos) = self.nodes[parent].children.iter().position(|&c| c == child) {
            self.nodes[parent].children.remove(pos);
            // self.nodes.remove(child);
            true
        } else {
            false
        }
    }

    pub fn contains_child(&self, parent: usize, child: usize) -> bool {
        self.nodes[parent].children.contains(&child)
    }

    pub fn has_child_nodes(&self, parent: usize) -> bool {
        !self.nodes[parent].children.is_empty()
    }

    #[inline(always)]
    pub fn node_from_id(&self, node_id: NodeId) -> &Node {
        &self.nodes[usize::from(node_id)]
    }

    #[inline(always)]
    pub fn node_from_id_mut(&mut self, node_id: NodeId) -> &mut Node {
        &mut self.nodes[usize::from(node_id)]
    }

    pub fn compute_layout(
        &mut self,
        root: usize,
        available_space: Size<AvailableSpace>,
        use_rounding: bool,
    ) {
        compute_root_layout(self, NodeId::from(root), available_space);
        if use_rounding {
            round_layout(self, NodeId::from(root))
        }
    }

    pub fn print_tree(&self, root: usize) {
        print_tree(self, NodeId::from(root));
    }

    pub fn to_string(&self, root: usize) -> String {
        // print_tree(self, NodeId::from(root));
        print_tree_to_string(self, NodeId::from(root))
    }
}

/// LuaTree is a Lua user data type that wraps the Tree structure.
pub struct LuaTree(pub Rc<RefCell<Tree>>);

impl LuaUserData for LuaTree {
    fn add_methods<M: mlua::UserDataMethods<Self>>(methods: &mut M) {
        methods.add_method_mut(
            "create_element",
            |lua, this, (kind_str, props_value): (String, Option<LuaValue>)| {
                let props_table: LuaTable = match props_value {
                    Some(LuaValue::Table(table)) => table,
                    Some(LuaValue::Nil) | None => lua.create_table()?,
                    _ => return Err(mlua::Error::external("Expected table or nil for props")),
                };
                let lua_props = LuaProps::new(props_table);

                let style: Style = lua_props.to_style();
                let node = Node::new_from_kind_str(kind_str, style);
                let node_id = this.0.borrow_mut().add_node(node);

                let lua_node = LuaNode::new(this.0.clone(), node_id);
                Ok(lua_node)
            },
        );
        methods.add_method_mut("create_text_node", |_, this, text_content: String| {
            let node = Node::new_text(TextContext {
                text_content,
                writing_mode: WritingMode::Horizontal,
            });
            let node_id = this.0.borrow_mut().add_node(node);

            let lua_node = LuaNode::new(this.0.clone(), node_id);
            Ok(lua_node)
        });
    }
}
