use std::cell::RefCell;
use std::rc::Rc;

use crate::common;
use crate::node::{node, LuaNode, LuaProps, Node, NodeKind};
use crate::tree::print::print_tree_to_string;

use common::image::{image_measure_function, ImageContext};
use common::text::{text_measure_function, FontMetrics, TextContext, WritingMode, LOREM_IPSUM};
use mlua::prelude::*;
use taffy::util::print_tree;
use taffy::{
    compute_block_layout, compute_cached_layout, compute_flexbox_layout, compute_grid_layout,
    compute_leaf_layout, compute_root_layout, prelude::*, round_layout, Cache, CacheTree,
};

#[derive(Default)]
pub struct Tree {
    nodes: Vec<Node>,
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

                let lua_node = LuaNode::new(this.0.clone(), NodeId::from(node_id));
                Ok(lua_node)

                // Ok(this.node_from_id(NodeId::from(node_id)))
            },
        );
        methods.add_method_mut("create_text_node", |_, this, text_content: String| {
            let node = Node::new_text(TextContext {
                text_content,
                writing_mode: WritingMode::Horizontal,
            });
            let node_id = this.0.borrow_mut().add_node(node);

            let lua_node = LuaNode::new(this.0.clone(), NodeId::from(node_id));
            Ok(lua_node)
        });

        methods.add_meta_method(LuaMetaMethod::ToString, |_, this, ()| {
            let mut output = String::new();
            for (i, node) in this.0.borrow_mut().nodes.iter().enumerate() {
                output.push_str(&format!(
                    "Node {}: {:?}, Style: {:?}, Children: {:?}\n",
                    i, node.kind, node.style, node.children
                ));
            }
            Ok(output)
        });
    }
}

pub struct ChildIter<'a>(std::slice::Iter<'a, usize>);
impl Iterator for ChildIter<'_> {
    type Item = NodeId;
    fn next(&mut self) -> Option<Self::Item> {
        self.0.next().copied().map(NodeId::from)
    }
}

impl taffy::TraversePartialTree for Tree {
    type ChildIter<'a> = ChildIter<'a>;

    fn child_ids(&self, node_id: NodeId) -> Self::ChildIter<'_> {
        ChildIter(self.node_from_id(node_id).children.iter())
    }

    fn child_count(&self, node_id: NodeId) -> usize {
        self.node_from_id(node_id).children.len()
    }

    fn get_child_id(&self, node_id: NodeId, index: usize) -> NodeId {
        NodeId::from(self.node_from_id(node_id).children[index])
    }
}

impl taffy::TraverseTree for Tree {}

impl taffy::LayoutPartialTree for Tree {
    // type CustomIdent = String;

    type CoreContainerStyle<'a>
        = &'a Style
    where
        Self: 'a;

    fn get_core_container_style(&self, node_id: NodeId) -> Self::CoreContainerStyle<'_> {
        &self.node_from_id(node_id).style
    }

    fn set_unrounded_layout(&mut self, node_id: NodeId, layout: &Layout) {
        self.node_from_id_mut(node_id).unrounded_layout = *layout;
    }

    fn resolve_calc_value(&self, _val: *const (), _basis: f32) -> f32 {
        0.0
    }

    fn compute_child_layout(
        &mut self,
        node_id: NodeId,
        inputs: taffy::tree::LayoutInput,
    ) -> taffy::tree::LayoutOutput {
        compute_cached_layout(self, node_id, inputs, |tree, node_id, inputs| {
            let node = &mut tree.nodes[usize::from(node_id)];
            let font_metrics = FontMetrics {
                char_width: 10.0,
                char_height: 10.0,
            };

            match node.kind {
                NodeKind::Flexbox => compute_flexbox_layout(tree, node_id, inputs),
                NodeKind::Grid => compute_grid_layout(tree, node_id, inputs),
                NodeKind::Block => compute_block_layout(tree, node_id, inputs),
                NodeKind::Text => compute_leaf_layout(
                    inputs,
                    &node.style,
                    |_val, _basis| 0.0,
                    |known_dimensions, available_space| {
                        text_measure_function(
                            known_dimensions,
                            available_space,
                            node.text_data.as_ref().unwrap(),
                            &font_metrics,
                        )
                    },
                ),
                NodeKind::Image => compute_leaf_layout(
                    inputs,
                    &node.style,
                    |_val, _basis| 0.0,
                    |known_dimensions, _available_space| {
                        image_measure_function(known_dimensions, node.image_data.as_ref().unwrap())
                    },
                ),
            }
        })
    }
}

impl CacheTree for Tree {
    fn cache_get(
        &self,
        node_id: NodeId,
        known_dimensions: Size<Option<f32>>,
        available_space: Size<AvailableSpace>,
        run_mode: taffy::RunMode,
    ) -> Option<taffy::LayoutOutput> {
        self.node_from_id(node_id)
            .cache
            .get(known_dimensions, available_space, run_mode)
    }

    fn cache_store(
        &mut self,
        node_id: NodeId,
        known_dimensions: Size<Option<f32>>,
        available_space: Size<AvailableSpace>,
        run_mode: taffy::RunMode,
        layout_output: taffy::LayoutOutput,
    ) {
        self.node_from_id_mut(node_id).cache.store(
            known_dimensions,
            available_space,
            run_mode,
            layout_output,
        )
    }

    fn cache_clear(&mut self, node_id: NodeId) {
        self.node_from_id_mut(node_id).cache.clear();
    }
}

impl taffy::LayoutFlexboxContainer for Tree {
    type FlexboxContainerStyle<'a>
        = &'a Style
    where
        Self: 'a;

    type FlexboxItemStyle<'a>
        = &'a Style
    where
        Self: 'a;

    fn get_flexbox_container_style(&self, node_id: NodeId) -> Self::FlexboxContainerStyle<'_> {
        &self.node_from_id(node_id).style
    }

    fn get_flexbox_child_style(&self, child_node_id: NodeId) -> Self::FlexboxItemStyle<'_> {
        &self.node_from_id(child_node_id).style
    }
}

impl taffy::LayoutGridContainer for Tree {
    type GridContainerStyle<'a>
        = &'a Style
    where
        Self: 'a;

    type GridItemStyle<'a>
        = &'a Style
    where
        Self: 'a;

    fn get_grid_container_style(&self, node_id: NodeId) -> Self::GridContainerStyle<'_> {
        &self.node_from_id(node_id).style
    }

    fn get_grid_child_style(&self, child_node_id: NodeId) -> Self::GridItemStyle<'_> {
        &self.node_from_id(child_node_id).style
    }
}

impl taffy::LayoutBlockContainer for Tree {
    type BlockContainerStyle<'a> = &'a Style;
    type BlockItemStyle<'a> = &'a Style;

    fn get_block_container_style(&self, node_id: NodeId) -> Self::BlockContainerStyle<'_> {
        &self.node_from_id(node_id).style
    }

    fn get_block_child_style(&self, child_node_id: NodeId) -> Self::BlockItemStyle<'_> {
        &self.node_from_id(child_node_id).style
    }
}

impl taffy::RoundTree for Tree {
    fn get_unrounded_layout(&self, node_id: NodeId) -> &Layout {
        &self.node_from_id(node_id).unrounded_layout
    }

    fn set_final_layout(&mut self, node_id: NodeId, layout: &Layout) {
        self.node_from_id_mut(node_id).final_layout = *layout;
    }
}

impl taffy::PrintTree for Tree {
    fn get_debug_label(&self, node_id: NodeId) -> &'static str {
        match self.node_from_id(node_id).kind {
            NodeKind::Flexbox => "FLEX",
            NodeKind::Grid => "GRID",
            NodeKind::Text => "TEXT",
            NodeKind::Image => "IMAGE",
            NodeKind::Block => "BLOCK",
        }
    }

    fn get_final_layout(&self, node_id: NodeId) -> &Layout {
        &self.node_from_id(node_id).final_layout
    }
}
