use crate::tree::traits::LayoutPartialTreeExt;
use std::cell::RefCell;
use std::rc::Rc;

use crate::compute::{compute_text_layout, LayoutTextContainer, TextContext, WritingMode};
use crate::node::{node, LuaNode, LuaProps, Node, NodeKind};
use crate::tree::print::print_tree_to_string;

use mlua::prelude::*;
use taffy::util::print_tree;
use taffy::{
    compute_block_layout, compute_cached_layout, compute_flexbox_layout, compute_grid_layout,
    compute_leaf_layout, compute_root_layout, prelude::*, round_layout, AbsoluteAxis, Cache,
    CacheTree, LayoutInput, LayoutOutput, RequestedAxis, RunMode, SizingMode,
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

    #[inline(always)]
    pub fn perform_child_layout(
        &mut self,
        node_id: NodeId,
        known_dimensions: Size<Option<f32>>,
        parent_size: Size<Option<f32>>,
        available_space: Size<AvailableSpace>,
        sizing_mode: SizingMode,
        vertical_margins_are_collapsible: Line<bool>,
    ) -> LayoutOutput {
        self.compute_child_layout(
            node_id,
            LayoutInput {
                known_dimensions,
                parent_size,
                available_space,
                sizing_mode,
                axis: RequestedAxis::Both,
                run_mode: RunMode::PerformLayout,
                vertical_margins_are_collapsible,
            },
        )
    }

    #[inline(always)]
    #[allow(clippy::too_many_arguments)]
    pub fn measure_child_size(
        &mut self,
        node_id: NodeId,
        known_dimensions: Size<Option<f32>>,
        parent_size: Size<Option<f32>>,
        available_space: Size<AvailableSpace>,
        sizing_mode: SizingMode,
        axis: AbsoluteAxis,
        vertical_margins_are_collapsible: Line<bool>,
    ) -> f32 {
        self.compute_child_layout(
            node_id,
            LayoutInput {
                known_dimensions,
                parent_size,
                available_space,
                sizing_mode,
                axis: axis.into(),
                run_mode: RunMode::ComputeSize,
                vertical_margins_are_collapsible,
            },
        )
        .size
        .get_abs(axis)
    }

    #[inline(always)]
    // #[cfg(feature = "calc")]
    pub fn calc(&self, val: *const (), basis: f32) -> f32 {
        self.resolve_calc_value(val, basis)
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
        let node = self.node_from_id(node_id);
        match node.kind {
            NodeKind::Flexbox => "FLEX",
            NodeKind::Grid => "GRID",
            NodeKind::Text => "TEXT",
            NodeKind::Block => "BLOCK",
            NodeKind::Inline => "INLINE",
        }
    }

    fn get_final_layout(&self, node_id: NodeId) -> &Layout {
        &self.node_from_id(node_id).final_layout
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

impl LayoutTextContainer for Tree {
    type TextContainerStyle<'a>
        = &'a Style
    where
        Self: 'a;

    type TextItemStyle<'a>
        = &'a Style
    where
        Self: 'a;

    fn get_text_container_style(&self, node_id: NodeId) -> Self::TextContainerStyle<'_> {
        &self.node_from_id(node_id).style
    }

    fn get_text_child_style(&self, child_node_id: NodeId) -> Self::TextItemStyle<'_> {
        &self.node_from_id(child_node_id).style
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

            match node.kind {
                NodeKind::Flexbox => compute_flexbox_layout(tree, node_id, inputs),
                NodeKind::Grid => compute_grid_layout(tree, node_id, inputs),
                NodeKind::Block => compute_block_layout(tree, node_id, inputs),
                NodeKind::Inline => compute_text_layout(tree, node_id, inputs),
                NodeKind::Text => compute_text_layout(tree, node_id, inputs),
                // NodeKind::Text => compute_leaf_layout(
                //     inputs,
                //     &node.style,
                //     |_val, _basis| 0.0,
                //     |known_dimensions, available_space| {
                //         text_measure_function(known_dimensions, available_space, node)
                //     },
                // ),
            }
        })
    }
}
