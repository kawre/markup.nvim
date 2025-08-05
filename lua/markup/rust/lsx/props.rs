use crate::prelude::*;
use mlua::prelude::*;
use taffy::prelude::*;

#[derive(Debug, Clone)]
pub struct LuaProps {
    base: LuaTable,
    pub children: Option<LuaPropsChildren>,

    // General
    pub display: Option<LuaDisplay>,
    pub width: Option<LuaDimension>,
    pub height: Option<LuaDimension>,
    pub min_width: Option<LuaDimension>,
    pub min_height: Option<LuaDimension>,
    pub max_width: Option<LuaDimension>,
    pub max_height: Option<LuaDimension>,
    pub aspect_ratio: Option<f32>,

    // Margin
    pub margin_left: Option<u32>,
    pub margin_right: Option<u32>,
    pub margin_top: Option<u32>,
    pub margin_bottom: Option<u32>,

    // Padding
    pub padding_left: Option<u32>,
    pub padding_right: Option<u32>,
    pub padding_top: Option<u32>,
    pub padding_bottom: Option<u32>,

    // Flexbox
    pub flex_direction: Option<String>,
    pub flex_wrap: Option<String>,
    pub flex_basis: Option<LuaDimension>,
    pub flex_grow: Option<f32>,
    pub flex_shrink: Option<f32>,

    // Alignment
    pub align_items: Option<String>,
    pub align_self: Option<String>,
    pub align_content: Option<String>,
    pub justify_content: Option<String>,
}

// impl LuaUserData for LuaProps {}

#[derive(Debug, Clone)]
pub struct LuaBoxSizing(BoxSizing);

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

#[derive(Debug, Clone)]
pub struct LuaDimension(Dimension);

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

#[derive(Debug, Clone)]
pub struct LuaDisplay(Display);

impl FromLua for LuaDisplay {
    fn from_lua(value: LuaValue, _: &Lua) -> LuaResult<Self> {
        match value {
            LuaValue::String(s) => {
                let s = s.to_str()?;
                match &*s {
                    "flex" => Ok(LuaDisplay(Display::Flex)),
                    "none" => Ok(LuaDisplay(Display::None)),
                    _ => Err(LuaError::external("Invalid display value")),
                }
            }
            _ => Err(LuaError::external("Expected a string for display")),
        }
    }
}

#[derive(Debug, Clone)]
pub struct LuaPropsChildren(Vec<LuaPropsChild>);

impl FromLua for LuaPropsChildren {
    fn from_lua(value: LuaValue, lua: &Lua) -> LuaResult<Self> {
        match value {
            LuaValue::Table(tbl) => {
                // check if array-like (sequence)
                if tbl.clone().len()? > 0 {
                    let mut children = Vec::new();
                    for val in tbl.sequence_values::<LuaValue>() {
                        let val = val?;
                        let child = LuaPropsChild::from_lua(val, lua)?;
                        children.push(child);
                    }
                    Ok(LuaPropsChildren(children))
                } else {
                    // empty table? treat as empty children list
                    Ok(LuaPropsChildren(Vec::new()))
                }
            }
            _ => {
                // single child
                let child = LuaPropsChild::from_lua(value, lua)?;
                Ok(LuaPropsChildren(vec![child]))
            }
        }
    }
}

#[derive(Debug, Clone)]
pub enum LuaPropsChild {
    Text(String),
    Number(i64),
    Lsx(LuaLsx),
}

impl FromLua for LuaPropsChild {
    fn from_lua(value: LuaValue, _: &Lua) -> LuaResult<Self> {
        match value {
            LuaValue::String(s) => Ok(LuaPropsChild::Text(s.to_str()?.to_string())),
            LuaValue::Integer(i) => Ok(LuaPropsChild::Number(i)),
            LuaValue::Number(n) => Ok(LuaPropsChild::Number(n as i64)),
            LuaValue::UserData(ud) => {
                if let Ok(lsx_ref) = ud.borrow::<LuaLsx>() {
                    Ok(LuaPropsChild::Lsx(lsx_ref.clone()))
                } else {
                    Err(LuaError::external("Expected LuaLsx user data"))
                }
            }
            _ => Err(LuaError::external("Invalid child type")),
        }
    }
}

impl FromLua for LuaProps {
    fn from_lua(value: LuaValue, lua: &Lua) -> LuaResult<Self> {
        let table = match value {
            LuaValue::Table(t) => t,
            _ => lua.create_table()?,
        };

        Ok(LuaProps {
            base: table.clone(),
            children: table.get("children")?,
            display: table.get("display")?,
            width: table.get("width")?,
            height: table.get("height")?,
            min_width: table.get("min_width")?,
            min_height: table.get("min_height")?,
            max_width: table.get("max_width")?,
            max_height: table.get("max_height")?,
            aspect_ratio: table.get("aspect_ratio")?,

            margin_left: table.get("margin_left")?,
            margin_right: table.get("margin_right")?,
            margin_top: table.get("margin_top")?,
            margin_bottom: table.get("margin_bottom")?,

            padding_left: table.get("padding_left")?,
            padding_right: table.get("padding_right")?,
            padding_top: table.get("padding_top")?,
            padding_bottom: table.get("padding_bottom")?,

            flex_direction: table.get("flex_direction")?,
            flex_wrap: table.get("flex_wrap")?,
            flex_basis: table.get("flex_basis")?,
            flex_grow: table.get("flex_grow")?,
            flex_shrink: table.get("flex_shrink")?,

            align_items: table.get("align_items")?,
            align_self: table.get("align_self")?,
            align_content: table.get("align_content")?,
            justify_content: table.get("justify_content")?,
        })
    }
}

impl PartialEq for LuaProps {
    fn eq(&self, other: &Self) -> bool {
        // Compare the Lua table pointers for identity
        self.base.to_pointer() == other.base.to_pointer()
    }
}
