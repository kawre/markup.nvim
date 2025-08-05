use crate::{
    compute::{LayoutInlineContainer, builder::ComputedLinesBuilder},
    node::{Node, NodeKind},
    style::{InlineContainerStyle, InlineItemStyle},
    tree::{LayoutPartialTreeExt, Tree, tree},
};

use taffy::{
    AbsoluteAxis, BoxGenerationMode, BoxSizing, CollapsibleMarginSet, CoreStyle, Layout,
    LayoutInput, LayoutOutput, LayoutPartialTree, LengthPercentageAuto, MaybeMath, NodeId,
    Overflow, Point, Position, Rect, ResolveOrZero, RunMode, Size, SizingMode, prelude::*,
};

#[allow(dead_code)]
pub enum WritingMode {
    Horizontal,
    Vertical,
}

pub struct TextChunk {
    pub text_content: String,
    pub display_width: i32,
}

pub struct TextContext {
    pub chunks: Vec<TextChunk>,
    pub writing_mode: WritingMode,
}

impl Default for TextContext {
    fn default() -> Self {
        Self {
            chunks: Vec::new(),
            writing_mode: WritingMode::Horizontal,
        }
    }
}

/// Per-child data that is accumulated and modified over the course of the layout algorithm
pub struct InlineItem {
    node_id: NodeId,
    highlight: Option<String>,
}

/// Computes the layout of [`LayoutPartialTree`] according to the block layout algorithm
pub fn compute_inline_layout(
    tree: &mut Tree,
    node_id: NodeId,
    inputs: LayoutInput,
) -> LayoutOutput {
    let LayoutInput {
        known_dimensions,
        run_mode,
        ..
    } = inputs;

    if run_mode == RunMode::ComputeSize {
        if let Size {
            width: Some(width),
            height: Some(height),
        } = known_dimensions
        {
            return LayoutOutput::from_outer_size(Size { width, height });
        }
    }

    compute_inner(tree, node_id, inputs)
}

fn compute_inner(tree: &mut Tree, node_id: NodeId, inputs: LayoutInput) -> LayoutOutput {
    let LayoutInput {
        available_space,
        run_mode,
        ..
    } = inputs;

    let style = tree.get_text_container_style(node_id);

    let raw_padding = style.padding();
    let raw_margin = style.margin();

    let raw_padding_right = raw_padding.right.into_raw().value();
    let raw_padding_left = raw_padding.left.into_raw().value();
    let raw_margin_right = raw_margin.right.into_raw().value();
    let raw_margin_left = raw_margin.left.into_raw().value();
    let horizontal_sum = raw_padding_left + raw_padding_right + raw_margin_left + raw_margin_right;

    // let mut chunks = Vec::new();
    // gather_text_chunks(tree, node_id, &mut chunks);
    drop(style);

    // 1. Generate items
    let items = generate_item_list(tree, node_id);

    perform_final_layout(tree, node_id, &items, available_space.width)
}

// struct

fn perform_final_layout(
    tree: &mut Tree,
    node_id: NodeId,
    items: &[InlineItem],
    available_width: AvailableSpace,
) -> LayoutOutput {
    let available_width = available_width.unwrap() as i32;
    let mut builder = ComputedLinesBuilder::new(available_width);

    for item in items.iter() {
        let node = tree.node_from_id(item.node_id);
        let text_data = node.text_data.as_ref().unwrap();

        for chunk in text_data.chunks.iter() {
            builder.push_chunk(chunk, item.highlight.as_ref());
        }
    }

    let final_size = Size {
        width: builder.width() as f32,
        height: builder.height() as f32,
    };

    LayoutOutput {
        size: final_size,
        content_size: final_size,
        first_baselines: Point::zero(),
        top_margin: CollapsibleMarginSet::ZERO,
        bottom_margin: CollapsibleMarginSet::ZERO,
        margins_can_collapse_through: false,
    }
}

#[inline]
fn generate_item_list(tree: &Tree, node_id: NodeId) -> Vec<InlineItem> {
    fn gather_inline_items(
        tree: &Tree,
        node_id: NodeId,
        inherited_highlight: Option<String>,
    ) -> Vec<InlineItem> {
        let mut items = vec![];
        let node = tree.node_from_id(node_id);

        let local_highlight = node.highlight.clone().or(inherited_highlight);

        for &child_idx in &node.children {
            let child_id = NodeId::from(child_idx);
            let child = tree.node_from_id(child_id);

            match child.kind {
                NodeKind::Inline => {
                    let child_highlight =
                        child.highlight.clone().or_else(|| local_highlight.clone());
                    items.extend(gather_inline_items(tree, child_id, child_highlight));
                }
                NodeKind::Text => {
                    items.push(InlineItem {
                        node_id: child_id,
                        highlight: local_highlight.clone(),
                    });
                }
                _ => {
                    // Ignore block/flex/etc
                    continue;
                }
            }
        }

        items
    }
    gather_inline_items(tree, node_id, None)
}
