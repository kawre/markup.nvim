mod text;

use taffy::Style;
pub use text::*;

impl TextContainerStyle for Style {
    #[inline(always)]
    fn highlight(&self) -> Option<&'static str> {
        Some("123")
    }
}

impl TextItemStyle for Style {
    #[inline(always)]
    fn is_table(&self) -> bool {
        false
    }
}

impl<T: TextContainerStyle> TextContainerStyle for &'_ T {
    #[inline(always)]
    fn highlight(&self) -> Option<&'static str> {
        (*self).highlight()
    }
}

impl<T: TextItemStyle> TextItemStyle for &'_ T {
    #[inline(always)]
    fn is_table(&self) -> bool {
        false
    }
}
