use crate::{
    node::Node,
    style::{TextContainerStyle, TextItemStyle},
    tree::{tree, Tree},
};
use taffy::{
    prelude::*, BoxSizing, CoreStyle, Layout, LayoutInput, LayoutOutput, LayoutPartialTree,
    LengthPercentageAuto, NodeId, Overflow, Point, Position, Rect, Size,
};

#[allow(dead_code)]
pub enum WritingMode {
    Horizontal,
    Vertical,
}

pub struct TextContext {
    pub text_content: String,
    pub writing_mode: WritingMode,
}

/// Per-child data that is accumulated and modified over the course of the layout algorithm
struct TextItem {
    /// The identifier for the associated node
    node_id: NodeId,

    /// The "source order" of the item. This is the index of the item within the children iterator,
    /// and controls the order in which the nodes are placed
    order: u32,

    /// Items that are tables don't have stretch sizing applied to them
    is_table: bool,

    /// The base size of this item
    size: Size<Option<f32>>,
    /// The minimum allowable size of this item
    min_size: Size<Option<f32>>,
    /// The maximum allowable size of this item
    max_size: Size<Option<f32>>,

    /// The overflow style of the item
    overflow: Point<Overflow>,
    /// The width of the item's scrollbars (if it has scrollbars)
    scrollbar_width: f32,

    /// The position style of the item
    position: Position,
    /// The final offset of this item
    inset: Rect<LengthPercentageAuto>,
    /// The margin of this item
    margin: Rect<LengthPercentageAuto>,
    /// The margin of this item
    padding: Rect<f32>,
    /// The margin of this item
    border: Rect<f32>,
    /// The sum of padding and border for this item
    padding_border_sum: Size<f32>,

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

pub trait LayoutTextContainer: LayoutPartialTree {
    /// The style type representing the text container's styles
    type TextContainerStyle<'a>: TextContainerStyle
    where
        Self: 'a;

    /// The style type representing each CSS Grid item's styles
    type TextItemStyle<'a>: TextItemStyle
    where
        Self: 'a;

    /// Get the container's styles
    fn get_text_container_style(&self, node_id: NodeId) -> Self::TextContainerStyle<'_>;

    /// Get the child's styles
    fn get_text_child_style(&self, child_node_id: NodeId) -> Self::TextItemStyle<'_>;
}

/// Computes the layout of [`LayoutPartialTree`] according to the block layout algorithm
pub fn compute_text_layout(
    tree: &mut impl LayoutTextContainer,
    node_id: NodeId,
    inputs: LayoutInput,
) -> LayoutOutput {
    LayoutOutput {
        size: Size::ZERO,
        content_size: todo!(),
        first_baselines: todo!(),
        top_margin: todo!(),
        bottom_margin: todo!(),
        margins_can_collapse_through: todo!(),
    }
}
