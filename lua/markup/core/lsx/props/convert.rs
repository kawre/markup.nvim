use crate::prelude::*;
use mlua::prelude::*;
use taffy::{TextAlign, prelude::*};

fn get_or_default<T>(table: &LuaTable, key: &str) -> LuaResult<T>
where
    T: FromLua + Default,
{
    match table.contains_key(key) {
        Ok(true) => Ok(table.raw_get::<T>(key)?),
        Ok(false) => Ok(T::default()),
        Err(e) => Err(e),
    }
}

impl TryFrom<PendingProps> for Style {
    type Error = LuaError;

    fn try_from(value: PendingProps) -> Result<Self, Self::Error> {
        let t = value.0;

        // match base {
        // Some(t) =>
        Ok(Style {
            display: get_or_default::<LuaDisplay>(&t, "display")?.into(),
            box_sizing: get_or_default::<LuaBoxSizing>(&t, "box_sizing")?.into(),
            size: Size {
                width: get_or_default::<LuaDimension>(&t, "width")?.into(),
                height: get_or_default::<LuaDimension>(&t, "height")?.into(),
            },
            min_size: Size {
                width: get_or_default::<LuaDimension>(&t, "min_width")?.into(),
                height: get_or_default::<LuaDimension>(&t, "min_height")?.into(),
            },
            max_size: Size {
                width: get_or_default::<LuaDimension>(&t, "max_width")?.into(),
                height: get_or_default::<LuaDimension>(&t, "max_height")?.into(),
            },
            margin: Rect {
                left: get_or_default::<LuaLengthPercentageAuto>(&t, "margin_left")?.into(),
                right: get_or_default::<LuaLengthPercentageAuto>(&t, "margin_right")?.into(),
                top: get_or_default::<LuaLengthPercentageAuto>(&t, "margin_top")?.into(),
                bottom: get_or_default::<LuaLengthPercentageAuto>(&t, "margin_bottom")?.into(),
            },
            padding: Rect {
                left: get_or_default::<LuaLengthPercentage>(&t, "padding_left")?.into(),
                right: get_or_default::<LuaLengthPercentage>(&t, "padding_right")?.into(),
                top: get_or_default::<LuaLengthPercentage>(&t, "padding_top")?.into(),
                bottom: get_or_default::<LuaLengthPercentage>(&t, "padding_bottom")?.into(),
            },
            gap: Size {
                width: get_or_default::<LuaLengthPercentage>(&t, "gap")?.into(),
                height: get_or_default::<LuaLengthPercentage>(&t, "gap")?.into(),
            },
            text_align: get_or_default::<LuaTextAlign>(&t, "text_align")?.into(),
            align_items: get_or_default::<LuaAlignItems>(&t, "align_items")?.into(),
            align_self: get_or_default::<LuaAlignItems>(&t, "align_self")?.into(),
            align_content: get_or_default::<LuaAlignContent>(&t, "align_content")?.into(),
            justify_items: get_or_default::<LuaAlignItems>(&t, "justify_items")?.into(),
            justify_content: get_or_default::<LuaAlignContent>(&t, "justify_content")?.into(),
            flex_direction: get_or_default::<LuaFlexDirection>(&t, "flex_direction")?.into(),
            flex_wrap: get_or_default::<LuaFlexWrap>(&t, "flex_wrap")?.into(),
            flex_grow: get_or_default::<f32>(&t, "flex_grow")?,
            flex_shrink: get_or_default::<f32>(&t, "flex_shrink")?,
            flex_basis: get_or_default::<LuaDimension>(&t, "flex_basis")?.into(),
            justify_self: get_or_default::<LuaAlignItems>(&t, "justify_self")?.into(),
            ..Default::default()
        })
        // None => Ok(Style::default()),
    }
}

// -----------------------------------------------------------------------------
// LuaBoxSizing
// -----------------------------------------------------------------------------
#[derive(Debug, Clone, Default)]
pub struct LuaBoxSizing(pub BoxSizing);
impl From<LuaBoxSizing> for BoxSizing {
    fn from(value: LuaBoxSizing) -> Self {
        value.0
    }
}
impl FromLua for LuaBoxSizing {
    fn from_lua(value: LuaValue, _: &Lua) -> LuaResult<Self> {
        match value {
            LuaValue::String(s) => {
                let s = s.to_str()?;
                match &*s {
                    "border-box" => Ok(LuaBoxSizing(BoxSizing::BorderBox)),
                    "content-box" => Ok(LuaBoxSizing(BoxSizing::ContentBox)),
                    _ => Err(LuaError::external("Invalid box-sizing value")),
                }
            }
            _ => Err(LuaError::external("Expected a string for box-sizing")),
        }
    }
}

// -----------------------------------------------------------------------------
// LuaDimension
// -----------------------------------------------------------------------------
#[derive(Debug, Clone)]
pub struct LuaDimension(pub Dimension);
impl From<LuaDimension> for Dimension {
    fn from(value: LuaDimension) -> Self {
        value.0
    }
}
impl Default for LuaDimension {
    fn default() -> Self {
        LuaDimension(Dimension::auto())
    }
}
impl FromLua for LuaDimension {
    fn from_lua(value: LuaValue, _: &Lua) -> LuaResult<Self> {
        match value {
            LuaValue::Integer(i) => Ok(LuaDimension(Dimension::length(i as f32))),
            LuaValue::Number(n) => {
                if n < 1.0 {
                    Ok(LuaDimension(Dimension::percent(n as f32)))
                } else {
                    Ok(LuaDimension(Dimension::length(n as f32)))
                }
            }
            LuaValue::String(s) => {
                let s = s.to_str()?;
                if s.ends_with('%') {
                    let percent: f32 = s.trim_end_matches('%').parse().map_err(|_| {
                        LuaError::external("Invalid percentage format for dimension")
                    })?;
                    Ok(LuaDimension(Dimension::percent(percent / 100.0)))
                } else if let Ok(length) = s.parse::<f32>() {
                    // TODO relative len
                    Ok(LuaDimension(Dimension::length(length)))
                } else if s == "auto" {
                    Ok(LuaDimension(Dimension::auto()))
                } else {
                    Err(LuaError::external("Invalid dimension format"))
                }
            }
            _ => Err(LuaError::external(
                "Expected an integer or number for dimension",
            )),
        }
    }
}

// -----------------------------------------------------------------------------
// LuaDisplay
// -----------------------------------------------------------------------------
#[derive(Debug, Clone, Default)]
pub struct LuaDisplay(pub Display);
impl From<LuaDisplay> for Display {
    fn from(value: LuaDisplay) -> Self {
        value.0
    }
}
impl FromLua for LuaDisplay {
    fn from_lua(value: LuaValue, _: &Lua) -> LuaResult<Self> {
        match value {
            LuaValue::String(s) => {
                let s = s.to_str()?;
                match &*s {
                    "flex" => Ok(LuaDisplay(Display::Flex)),
                    "block" => Ok(LuaDisplay(Display::Block)),
                    "none" => Ok(LuaDisplay(Display::None)),
                    _ => Err(LuaError::external("Invalid display value")),
                }
            }
            _ => Err(LuaError::external("Expected a string for display")),
        }
    }
}

// -----------------------------------------------------------------------------
// LuaLengthPercentage
// -----------------------------------------------------------------------------
#[derive(Debug, Clone)]
pub struct LuaLengthPercentage(pub LengthPercentage);
impl Default for LuaLengthPercentage {
    fn default() -> Self {
        LuaLengthPercentage(LengthPercentage::length(0.0))
    }
}
impl From<LuaLengthPercentage> for LengthPercentage {
    fn from(value: LuaLengthPercentage) -> Self {
        value.0
    }
}
impl FromLua for LuaLengthPercentage {
    fn from_lua(value: LuaValue, _: &Lua) -> LuaResult<Self> {
        Ok(LuaLengthPercentage(LengthPercentage::length(100.0)))
    }
}

// -----------------------------------------------------------------------------
// LuaLengthPercentageAuto
// -----------------------------------------------------------------------------
#[derive(Debug, Clone)]
pub struct LuaLengthPercentageAuto(pub LengthPercentageAuto);

impl Default for LuaLengthPercentageAuto {
    fn default() -> Self {
        LuaLengthPercentageAuto(LengthPercentageAuto::length(0.0))
    }
}
impl From<LuaLengthPercentageAuto> for LengthPercentageAuto {
    fn from(value: LuaLengthPercentageAuto) -> Self {
        value.0
    }
}
impl FromLua for LuaLengthPercentageAuto {
    fn from_lua(value: LuaValue, _: &Lua) -> LuaResult<Self> {
        Ok(LuaLengthPercentageAuto(LengthPercentageAuto::length(100.0)))
    }
}

// -----------------------------------------------------------------------------
// LuaTextAlign
// -----------------------------------------------------------------------------
#[derive(Debug, Clone, Default)]
pub struct LuaTextAlign(pub TextAlign);
impl From<LuaTextAlign> for TextAlign {
    fn from(value: LuaTextAlign) -> Self {
        value.0
    }
}
impl FromLua for LuaTextAlign {
    fn from_lua(value: LuaValue, _: &Lua) -> LuaResult<Self> {
        match value {
            LuaValue::String(s) => match &*s.to_str()? {
                "auto" => Ok(LuaTextAlign(TextAlign::Auto)),
                "left" | "start" => Ok(LuaTextAlign(TextAlign::LegacyLeft)),
                "right" | "end" => Ok(LuaTextAlign(TextAlign::LegacyRight)),
                "center" => Ok(LuaTextAlign(TextAlign::LegacyCenter)),
                other => Err(LuaError::external(format!(
                    "Invalid text-align `{}`",
                    other
                ))),
            },
            _ => Err(LuaError::external("Expected string for text-align")),
        }
    }
}

// -----------------------------------------------------------------------------
// LuaAlignItems (also covers justify_items & justify_self/align_self)
// -----------------------------------------------------------------------------
#[derive(Debug, Clone, Default)]
pub struct LuaAlignItems(pub Option<AlignItems>);
impl From<LuaAlignItems> for Option<AlignItems> {
    fn from(value: LuaAlignItems) -> Self {
        value.0
    }
}
impl FromLua for LuaAlignItems {
    fn from_lua(value: LuaValue, _: &Lua) -> LuaResult<Self> {
        match value {
            LuaValue::String(s) => match &*s.to_str()? {
                "flex-start" | "start" => Ok(LuaAlignItems(Some(AlignItems::Start))),
                "flex-end" | "end" => Ok(LuaAlignItems(Some(AlignItems::End))),
                "center" => Ok(LuaAlignItems(Some(AlignItems::Center))),
                "baseline" => Ok(LuaAlignItems(Some(AlignItems::Baseline))),
                "stretch" => Ok(LuaAlignItems(Some(AlignItems::Stretch))),
                other => Err(LuaError::external(format!(
                    "Invalid align-items `{}`",
                    other
                ))),
            },
            _ => Err(LuaError::external("Expected string for align-items")),
        }
    }
}

// -----------------------------------------------------------------------------
// LuaAlignContent
// -----------------------------------------------------------------------------
#[derive(Debug, Clone, Default)]
pub struct LuaAlignContent(pub Option<AlignContent>);
impl From<LuaAlignContent> for Option<AlignContent> {
    fn from(value: LuaAlignContent) -> Self {
        value.0
    }
}
impl FromLua for LuaAlignContent {
    fn from_lua(value: LuaValue, _: &Lua) -> LuaResult<Self> {
        match value {
            LuaValue::String(s) => match &*s.to_str()? {
                "flex-start" | "start" => Ok(LuaAlignContent(Some(AlignContent::Start))),
                "flex-end" | "end" => Ok(LuaAlignContent(Some(AlignContent::End))),
                "center" => Ok(LuaAlignContent(Some(AlignContent::Center))),
                "space-between" => Ok(LuaAlignContent(Some(AlignContent::SpaceBetween))),
                "space-around" => Ok(LuaAlignContent(Some(AlignContent::SpaceAround))),
                "stretch" => Ok(LuaAlignContent(Some(AlignContent::Stretch))),
                other => Err(LuaError::external(format!(
                    "Invalid align-content `{}`",
                    other
                ))),
            },
            _ => Err(LuaError::external("Expected string for align-content")),
        }
    }
}

// -----------------------------------------------------------------------------
// LuaFlexDirection
// -----------------------------------------------------------------------------
#[derive(Debug, Clone, Default)]
pub struct LuaFlexDirection(pub FlexDirection);
impl From<LuaFlexDirection> for FlexDirection {
    fn from(value: LuaFlexDirection) -> Self {
        value.0
    }
}
impl FromLua for LuaFlexDirection {
    fn from_lua(value: LuaValue, _: &Lua) -> LuaResult<Self> {
        match value {
            LuaValue::String(s) => match &*s.to_str()? {
                "row" => Ok(LuaFlexDirection(FlexDirection::Row)),
                "column" => Ok(LuaFlexDirection(FlexDirection::Column)),
                "row-reverse" => Ok(LuaFlexDirection(FlexDirection::RowReverse)),
                "column-reverse" => Ok(LuaFlexDirection(FlexDirection::ColumnReverse)),
                other => Err(LuaError::external(format!(
                    "Invalid flex-direction `{}`",
                    other
                ))),
            },
            _ => Err(LuaError::external("Expected string for flex-direction")),
        }
    }
}

// -----------------------------------------------------------------------------
// LuaFlexWrap
// -----------------------------------------------------------------------------
#[derive(Debug, Clone, Default)]
pub struct LuaFlexWrap(pub FlexWrap);
impl From<LuaFlexWrap> for FlexWrap {
    fn from(value: LuaFlexWrap) -> Self {
        value.0
    }
}
impl FromLua for LuaFlexWrap {
    fn from_lua(value: LuaValue, _: &Lua) -> LuaResult<Self> {
        match value {
            LuaValue::String(s) => match &*s.to_str()? {
                "nowrap" => Ok(LuaFlexWrap(FlexWrap::NoWrap)),
                "wrap" => Ok(LuaFlexWrap(FlexWrap::Wrap)),
                "wrap-reverse" => Ok(LuaFlexWrap(FlexWrap::WrapReverse)),
                other => Err(LuaError::external(format!("Invalid flex-wrap `{}`", other))),
            },
            _ => Err(LuaError::external("Expected string for flex-wrap")),
        }
    }
}
