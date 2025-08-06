use crate::prelude::*;
use mlua::prelude::*;
use taffy::prelude::*;

#[derive(Debug, Clone)]
pub struct LuaProps {
    base: LuaTable,
    pub children: LuaPropsChildren,
}

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

// pub struct LuaPropsChildren(Vec<LuaPropsChild>);
#[derive(Debug, Clone, Default)]
pub enum LuaPropsChildren {
    #[default]
    None,
    Text(String),
    Sequence(Vec<LuaPropsChild>),
}

impl FromLua for LuaPropsChildren {
    fn from_lua(value: LuaValue, lua: &Lua) -> LuaResult<Self> {
        match value {
            LuaValue::Table(t) => {
                // let children = t
                //     .pairs::<LuaValue, LuaPropsChild>()
                //     .filter_map(|res| {
                //         match res {
                //             Ok((LuaValue::Integer(_), LuaPropsChild::None)) => None, // skip empty
                //             Ok((LuaValue::Integer(_), child)) => Some(Ok(child)),
                //             //                          Ok((LuaValue::Integer(_), v)) => LuaPropsChild::from_lua(v, lua).ok(),
                //             // _ => None,
                //             Ok(_) => None, // skip non-integer keys
                //             Err(e) => Some(Err(e)),
                //         }
                //     })
                //     .collect::<LuaResult<Vec<_>>>()?;

                let mut children = Vec::new();

                for pair in t.pairs::<LuaValue, LuaValue>() {
                    if let Ok((LuaValue::Integer(_), value)) = pair {
                        match value {
                            LuaValue::Nil | LuaValue::Boolean(false) => continue,
                            _ => {
                                if let Ok(child) = LuaPropsChild::from_lua(value, lua) {
                                    children.push(child);
                                }
                            }
                        }
                    }
                }

                if children.is_empty() {
                    Ok(LuaPropsChildren::None)
                } else {
                    Ok(LuaPropsChildren::Sequence(children))
                }
            }
            LuaValue::String(s) => Ok(LuaPropsChildren::Text(s.to_str()?.to_string())),
            LuaValue::Integer(i) => Ok(LuaPropsChildren::Text(i.to_string())),
            LuaValue::Number(n) => Ok(LuaPropsChildren::Text(n.to_string())),
            LuaValue::Boolean(true) => Ok(LuaPropsChildren::Text("true".to_string())),
            LuaValue::Boolean(false) | LuaValue::Nil => Ok(LuaPropsChildren::None),
            _ => {
                let child = LuaPropsChild::from_lua(value, lua)?;
                Ok(LuaPropsChildren::Sequence(vec![child]))
            }
        }
    }
}

#[derive(Debug, Clone)]
pub enum LuaPropsChild {
    Text(String),
    Table(LuaTable), // table to treat as a fragment
    Element(LuaElement),
}

impl FromLua for LuaPropsChild {
    fn from_lua(value: LuaValue, _: &Lua) -> LuaResult<Self> {
        match value {
            LuaValue::String(s) => Ok(LuaPropsChild::Text(s.to_str()?.to_string())),
            LuaValue::Integer(i) => Ok(LuaPropsChild::Text(i.to_string())),
            LuaValue::Number(n) => Ok(LuaPropsChild::Text(n.to_string())),
            LuaValue::Boolean(true) => Ok(LuaPropsChild::Text("true".to_string())),
            LuaValue::Table(t) => Ok(LuaPropsChild::Table(t)),
            LuaValue::UserData(ud) => {
                if let Ok(lsx_ref) = ud.borrow::<LuaElement>() {
                    Ok(LuaPropsChild::Element(lsx_ref.clone()))
                } else {
                    Err(LuaError::external("Expected LuaLsx user data"))
                }
            }
            _ => Err(LuaError::external("Invalid child type")),
        }
    }
}

impl FromLua for LuaElementProps {
    fn from_lua(value: LuaValue, lua: &Lua) -> LuaResult<Self> {
        match value {
            LuaValue::String(s) => Ok(LuaPropsChild::Text(s.to_str()?.to_string())),
            LuaValue::Integer(i) => Ok(LuaPropsChild::Text(i.to_string())),
            LuaValue::Number(n) => Ok(LuaPropsChild::Text(n.to_string())),
        }
    }
}

impl PartialEq for LuaProps {
    fn eq(&self, other: &Self) -> bool {
        self.base.to_pointer() == other.base.to_pointer()
    }
}
