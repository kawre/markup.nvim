mod inline;
pub use inline::*;

use serde::Deserialize;
use taffy::{Dimension, Size, Style, prelude::TaffyAuto};

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

#[derive(Debug, Deserialize)]
pub struct LuaStyle {
    width: Option<f32>,
    height: Option<f32>,
    min_width: Option<f32>,
    min_height: Option<f32>,
    max_width: Option<f32>,
    max_height: Option<f32>,
    margin_left: Option<f32>,
    margin_right: Option<f32>,
    margin_top: Option<f32>,
    margin_bottom: Option<f32>,
    padding_left: Option<f32>,
    padding_right: Option<f32>,
    padding_top: Option<f32>,
    padding_bottom: Option<f32>,
    highlight: Option<String>,
}

impl From<LuaStyle> for Style {
    fn from(lua: LuaStyle) -> Self {
        Style {
            ..Default::default()
        }
    }
}
