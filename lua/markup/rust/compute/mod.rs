mod builder;
mod inline;

pub use builder::*;
pub use inline::*;
use taffy::{LayoutPartialTree, NodeId};

use crate::style::{InlineContainerStyle, InlineItemStyle};

pub trait LayoutInlineContainer: LayoutPartialTree {
    /// The style type representing the text container's styles
    type TextContainerStyle<'a>: InlineContainerStyle
    where
        Self: 'a;

    /// The style type representing each CSS Grid item's styles
    type TextItemStyle<'a>: InlineItemStyle
    where
        Self: 'a;

    /// Get the container's styles
    fn get_text_container_style(&self, node_id: NodeId) -> Self::TextContainerStyle<'_>;

    /// Get the child's styles
    fn get_text_child_style(&self, child_node_id: NodeId) -> Self::TextItemStyle<'_>;
}
