use crate::{
    compute::LayoutInlineContainer,
    node::Node,
    style::{InlineContainerStyle, InlineItemStyle},
    tree::{LayoutPartialTreeExt, Tree, tree},
};

use taffy::{
    BoxGenerationMode, BoxSizing, CollapsibleMarginSet, CoreStyle, Layout, LayoutInput,
    LayoutOutput, LayoutPartialTree, LengthPercentageAuto, MaybeMath, NodeId, Overflow, Point,
    Position, Rect, ResolveOrZero, RunMode, Size, SizingMode, prelude::*,
};

#[allow(dead_code)]
pub enum WritingMode {
    Horizontal,
    Vertical,
}

pub struct TextChunk {
    pub text_content: String,
    pub display_width: f32,
}

pub struct TextContext {
    pub chunks: Vec<TextChunk>,
    pub writing_mode: WritingMode,

    // Available for use after layout
    pub computed_text_content: Option<String>,
    pub computed_display_width: Option<f32>,
}

/// Per-child data that is accumulated and modified over the course of the layout algorithm
struct InlineItem {
    /// The identifier for the associated node
    node_id: NodeId,

    /// The "source order" of the item. This is the index of the item within the children iterator,
    /// and controls the order in which the nodes are placed
    order: u32,

    size: Size<Option<f32>>,

    /// Items that are tables don't have stretch sizing applied to them
    is_table: bool,

    // margin_left: f32,
    // margin_right: f32,
    //
    // padding_left: f32,
    // padding_right: f32,
    margin: Rect<LengthPercentageAuto>,
    padding: Rect<LengthPercentage>,

    /// The computed border box size of this item
    computed_size: Size<f32>,
    /// The computed "static position" of this item. The static position is the position
    /// taking into account padding, border, margins, and scrollbar_gutters but not inset
    static_position: Point<f32>,
    /// Whether margins can be collapsed through this item
    can_be_collapsed_through: bool,
}

pub fn text_measure_function(
    known_dimensions: taffy::geometry::Size<Option<f32>>,
    available_space: taffy::geometry::Size<taffy::style::AvailableSpace>,
    node: &Node,
) -> taffy::geometry::Size<f32> {
    use taffy::geometry::AbsoluteAxis;
    use taffy::prelude::*;

    // let continuation = TextContinuation {
    //     block: 0,
    //     inline_start: 0,
    //     inline_end: 0,
    //     text_content: String::new(),
    //     next: None,
    // };

    let mut text_context = String::new();

    // fn traverse_text_layout(node: &Node, text_content: &mut String) {
    //     let ctx = node.text_data.as_ref().unwrap();
    //     text_content.push_str(ctx.text_content.as_ref());
    //     node.children.iter().for_each(|&child_id| {
    //         let child_node = node.tree.node_from_id(child_id);
    //         traverse_text_layout(child_node, text_content);
    //     });
    // }
    // traverse_text_layout(node, &mut text_context);

    let words: Vec<&str> = text_context.split_whitespace().collect();
    let text_context = node.text_data.as_ref().unwrap();
    let inline_axis = match text_context.writing_mode {
        WritingMode::Horizontal => AbsoluteAxis::Horizontal,
        WritingMode::Vertical => AbsoluteAxis::Vertical,
    };
    let block_axis = inline_axis.other_axis();

    let min_line_length: usize = words.iter().map(|line| line.len()).max().unwrap_or(0);
    let max_line_length: usize = words.iter().map(|line| line.len()).sum();
    let inline_size =
        known_dimensions.get_abs(inline_axis).unwrap_or_else(|| {
            match available_space.get_abs(inline_axis) {
                AvailableSpace::MinContent => min_line_length as f32,
                AvailableSpace::MaxContent => max_line_length as f32,
                AvailableSpace::Definite(inline_size) => inline_size
                    .min(max_line_length as f32)
                    .max(min_line_length as f32),
            }
        });

    // let highlight_ranges: Vec<HighlightRange> = Vec::new();
    let block_size = known_dimensions.get_abs(block_axis).unwrap_or_else(|| {
        let inline_line_length = inline_size.floor() as usize;
        let mut line_count = 1;
        let mut current_line_length = 0;
        for word in &words {
            if current_line_length == 0 {
                // first word
                current_line_length = word.len();
            } else if current_line_length + word.len() + 1 > inline_line_length {
                // every word past the first needs to check for line length including the space between words
                // note: a real implementation of this should handle whitespace characters other than ' '
                // and do something more sophisticated for long words
                line_count += 1;
                current_line_length = word.len();
            } else {
                // add the word and a space
                current_line_length += word.len() + 1;
            };
        }
        line_count as f32
    });

    match text_context.writing_mode {
        WritingMode::Horizontal => Size {
            width: inline_size,
            height: block_size,
        },
        WritingMode::Vertical => Size {
            width: block_size,
            height: inline_size,
        },
    }
}

/// Computes the layout of [`LayoutPartialTree`] according to the block layout algorithm
pub fn compute_inline_layout(
    tree: &mut impl LayoutInlineContainer,
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

fn compute_inner(
    tree: &mut impl LayoutInlineContainer,
    node_id: NodeId,
    inputs: LayoutInput,
) -> LayoutOutput {
    let LayoutInput {
        known_dimensions,
        parent_size,
        available_space,
        run_mode,
        vertical_margins_are_collapsible,
        ..
    } = inputs;

    let style = tree.get_text_container_style(node_id);
    let raw_padding = style.padding();
    let raw_padding_right = raw_padding.right;
    let raw_padding_left = raw_padding.left;
    let raw_margin_right = style.margin().right;
    let raw_margin_left = style.margin().left;
    let color = style.highlight();

    drop(style);

    // 1. Generate items
    let mut items = generate_item_list(tree, node_id);

    // 2. Compute container width
    let container_outer_width = known_dimensions.width.unwrap_or_else(|| {
        let available_width = available_space.width;
        determine_content_based_container_width(tree, &items, available_width)
    });

    // Short-circuit if computing size and both dimensions known
    if let (RunMode::ComputeSize, Some(container_outer_height)) =
        (run_mode, known_dimensions.height)
    {
        return LayoutOutput::from_outer_size(Size {
            width: container_outer_width,
            height: container_outer_height,
        });
    }

    // 3. Perform final item layout and return content height
    let resolved_padding = raw_padding
        .resolve_or_zero(Some(container_outer_width), |val, basis| {
            tree.calc(val, basis)
        });
    let resolved_content_box_inset = resolved_padding;
    let (
        inflow_content_size,
        intrinsic_outer_height,
        first_child_top_margin_set,
        last_child_bottom_margin_set,
    ) = perform_final_layout_on_in_flow_children(tree, &mut items, container_outer_width);
    let container_outer_height = known_dimensions.height.unwrap_or(intrinsic_outer_height);
    let final_outer_size = Size {
        width: container_outer_width,
        height: container_outer_height,
    };

    // Short-circuit if computing size
    if run_mode == RunMode::ComputeSize {
        return LayoutOutput::from_outer_size(final_outer_size);
    }

    // 5. Perform hidden layout on hidden children
    let len = tree.child_count(node_id);
    for order in 0..len {
        let child = tree.get_child_id(node_id, order);
        if tree.get_text_child_style(child).box_generation_mode() == BoxGenerationMode::None {
            tree.set_unrounded_layout(child, &Layout::with_order(order as u32));
            tree.perform_child_layout(
                child,
                Size::NONE,
                Size::NONE,
                Size::MAX_CONTENT,
                SizingMode::InherentSize,
                Line::FALSE,
            );
        }
    }

    // #[cfg_attr(not(feature = "content_size"), allow(unused_variables))]
    let content_size = Size {
        width: 0.0,
        height: 0.0,
    };

    LayoutOutput {
        size: final_outer_size,
        content_size,
        first_baselines: Point::NONE,
        top_margin: CollapsibleMarginSet::ZERO,
        bottom_margin: CollapsibleMarginSet::ZERO,
        margins_can_collapse_through: false,
    }
}

#[inline]
fn generate_item_list(tree: &impl LayoutInlineContainer, node: NodeId) -> Vec<InlineItem> {
    tree.child_ids(node)
        .map(|child_node_id| (child_node_id, tree.get_text_child_style(child_node_id)))
        .filter(|(_, style)| style.box_generation_mode() != BoxGenerationMode::None)
        .enumerate()
        .map(|(order, (child_node_id, child_style))| {
            let padding = child_style.padding();
            let margin = child_style.margin();

            InlineItem {
                node_id: child_node_id,
                order: order as u32,
                is_table: child_style.is_table(),

                margin,
                padding,

                // Fields to be computed later (for now we initialise with dummy values)
                size: Size::zero(),
                computed_size: Size::zero(),
                static_position: Point::zero(),
                can_be_collapsed_through: false,
            }
        })
        .collect()
}

/// Compute the content-based width in the case that the width of the container is not known
#[inline]
fn determine_content_based_container_width(
    tree: &mut impl LayoutPartialTree,
    items: &[InlineItem],
    available_width: AvailableSpace,
) -> f32 {
    let available_space = Size {
        width: available_width,
        height: AvailableSpace::MinContent,
    };

    let mut max_child_width = 0.0;
    for item in items.iter() {
        let known_dimensions = item.size;

        let width = known_dimensions.width.unwrap_or_else(|| {
            let margin = item
                .margin
                .resolve_or_zero(available_space.width.into_option(), |val, basis| {
                    tree.resolve_calc_value(val, basis)
                });
            let item_x_margin_sum = margin.left + margin.right;
            let size_and_baselines = tree.perform_child_layout(
                item.node_id,
                known_dimensions,
                Size::NONE,
                available_space.map_width(|w| w.maybe_sub(item_x_margin_sum)),
                SizingMode::InherentSize,
                Line::TRUE,
            );

            size_and_baselines.size.width + item_x_margin_sum
        });
        // let width = f32_max(width, item.padding_border_sum.width);

        max_child_width += width;
    }

    max_child_width
}

/// Compute each child's final size and position
#[inline]
fn perform_final_layout_on_in_flow_children(
    tree: &mut impl LayoutPartialTree,
    items: &mut [InlineItem],
    container_outer_width: f32,
) -> (Size<f32>, f32, CollapsibleMarginSet, CollapsibleMarginSet) {
    // let mut first_child_top_margin_set = CollapsibleMarginSet::default();
    // let mut last_child_bottom_margin_set = CollapsibleMarginSet::default();

    // Compute the size and position of each item
    for item in items.iter_mut() {
        let known_dimensions = item.size;
        let available_space = Size {
            width: AvailableSpace::Definite(container_outer_width),
            height: AvailableSpace::MinContent,
        };

        let size_and_baselines = tree.perform_child_layout(
            item.node_id,
            known_dimensions,
            Size::NONE,
            available_space,
            SizingMode::InherentSize,
            Line::TRUE,
        );

        item.computed_size = size_and_baselines.size;
        // item.static_position = Point {
        //     x: content_box_inset.left + item.padding.left + item.margin.left,
        //     y: content_box_inset.top + item.padding.top + item.margin.top,
        // };
        // item.can_be_collapsed_through = own_margins_collapse_with_children.all();

        // // Update the first and last child margin sets
        // if item.order == 0 {
        //     first_child_top_margin_set.set(item.node_id, item.margin.top);
        // }
        // if item.order == items.len() as u32 - 1 {
        //     last_child_bottom_margin_set.set(item.node_id, item.margin.bottom);
        // }
    }

    // Compute the total content size
    let content_size = Size {
        width: container_outer_width,
        height: items.iter().map(|item| item.computed_size.height).sum(),
    };

    // Compute the intrinsic outer height
    let intrinsic_outer_height = content_size.height;

    (
        content_size,
        intrinsic_outer_height,
        CollapsibleMarginSet::ZERO,
        CollapsibleMarginSet::ZERO,
    )
}
