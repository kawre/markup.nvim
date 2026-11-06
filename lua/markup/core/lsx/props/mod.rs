mod convert;
// mod lua;

pub use convert::*;
// pub use lua::*;

use std::rc::Rc;

use crate::prelude::*;
use mlua::prelude::*;
use taffy::prelude::*;

// #[derive(Debug)]
// pub enum PendingProps {
//     Text(String),
//     Table(LuaTable, ElementChildren),
// }
#[derive(Debug)]
pub struct PendingProps(pub LuaTable);

#[derive(Debug, Clone)]
pub enum MemoizedProps {
    Text(String),
    Table(Rc<LuaRegistryKey>),
}

#[derive(Debug)]
pub enum ElementChildren {
    Single(ElementChild),
    Sequence(Vec<ElementChild>),
}

impl FromLua for ElementChildren {
    fn from_lua(value: LuaValue, lua: &Lua) -> LuaResult<Self> {
        match value {
            LuaValue::Table(ref t) => {
                if is_element(t)? {
                    let element = ElementChild::from_lua(value, lua)?;
                    Ok(ElementChildren::Single(element))
                } else {
                    let seq = t
                        .sequence_values::<ElementChild>()
                        .collect::<LuaResult<Vec<_>>>()?;
                    Ok(ElementChildren::Sequence(seq))
                }
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
    Table(LuaRegistryKey),   // simple table
    Element(LuaRegistryKey), // element table
}

fn is_element(value: &LuaTable) -> LuaResult<bool> {
    if let Some(mt) = value.metatable() {
        match mt.get::<LuaValue>("__type") {
            Ok(LuaValue::String(_)) => Ok(true),
            _ => Ok(false),
        }
    } else {
        Ok(false)
    }
}

impl FromLua for ElementChild {
    fn from_lua(value: LuaValue, lua: &Lua) -> LuaResult<Self> {
        match value {
            LuaValue::Table(t) => {
                let key = lua.create_registry_value(&t)?;
                if is_element(&t)? {
                    Ok(ElementChild::Element(key))
                } else {
                    Ok(ElementChild::Table(key))
                }
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
