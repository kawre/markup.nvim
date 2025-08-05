mod inline;

pub use inline::*;

use taffy::prelude::*;

impl InlineContainerStyle for Style {
    #[inline(always)]
    fn highlight(&self) -> Option<&'static str> {
        Some("123")
    }
}

impl InlineItemStyle for Style {
    #[inline(always)]
    fn is_table(&self) -> bool {
        false
    }
}

impl<T: InlineContainerStyle> InlineContainerStyle for &'_ T {
    #[inline(always)]
    fn highlight(&self) -> Option<&'static str> {
        (*self).highlight()
    }
}

impl<T: InlineItemStyle> InlineItemStyle for &'_ T {
    #[inline(always)]
    fn is_table(&self) -> bool {
        false
    }
}
