//! Style types for Block layout

use taffy::CoreStyle;

pub enum TextHighlight {
    Inherit,
}

/// The set of styles required for a Block layout container
pub trait InlineContainerStyle: CoreStyle {
    /// Defines buffer highlighting for the container.
    #[inline(always)]
    fn highlight(&self) -> Option<&'static str> {
        None
    }
}

/// The set of styles required for a Block layout item (child of a Block container)
pub trait InlineItemStyle: CoreStyle {
    /// Whether the item is a table. Table children are handled specially in block layout.
    #[inline(always)]
    fn is_table(&self) -> bool {
        false
    }
}
