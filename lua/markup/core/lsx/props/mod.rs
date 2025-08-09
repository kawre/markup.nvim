// mod convert;
// mod lua;

// pub use convert::*;
// pub use lua::*;

use crate::prelude::*;
use mlua::prelude::*;
use taffy::prelude::*;

#[derive(Debug)]
pub enum PendingProps {
    Text(String),
    Table(LuaTable, ElementChildren),
}

#[derive(Debug)]
pub enum MemoizedProps {
    Text(String),
    Table(LuaRegistryKey),
}

impl FromLua for PendingProps {
    fn from_lua(value: LuaValue, _: &Lua) -> LuaResult<Self> {
        match value {
            LuaValue::Table(tbl) => {
                let children: ElementChildren = tbl.get("children")?;
                Ok(PendingProps::Table(tbl, children))
            }
            LuaValue::String(s) => Ok(PendingProps::Text(s.to_str()?.to_string())),
            _ => Err(LuaError::external("Expected LuaTable for PendingProps")),
        }
    }
}

#[derive(Debug)]
pub enum ElementChildren {
    Single(ElementChild),
    Sequence(Vec<ElementChild>),
}

impl FromLua for ElementChildren {
    fn from_lua(value: LuaValue, lua: &Lua) -> LuaResult<Self> {
        match value {
            LuaValue::Table(t) => {
                let seq = t
                    .sequence_values::<ElementChild>()
                    .collect::<LuaResult<Vec<_>>>()?;
                Ok(ElementChildren::Sequence(seq))
            }
            value => {
                let child = ElementChild::from_lua(value, lua)?;
                Ok(ElementChildren::Single(child))
            }
        }
    }
}

#[derive(Debug)]
pub enum ElementChild {
    Text(String),
    // store only the registry key for the table
    // this is done to ensure that only a few references are kept on lua stack
    // and to avoid auxiliary stack overflow when processing large number of children
    Table(LuaRegistryKey),
}

impl FromLua for ElementChild {
    fn from_lua(value: LuaValue, lua: &Lua) -> LuaResult<Self> {
        match value {
            LuaValue::Table(t) => {
                let key = lua.create_registry_value(t)?;
                Ok(ElementChild::Table(key))
            }
            value => match lua.coerce_string(value) {
                Ok(s) => Ok(ElementChild::Text(match s {
                    Some(s) => s.to_str()?.to_string(),
                    None => return Err(LuaError::external("Expected a string")),
                })),
                Err(_) => Err(LuaError::external(
                    "Expected LuaTable, String, or UserData for ElementChild",
                )),
            },
        }
    }
}
