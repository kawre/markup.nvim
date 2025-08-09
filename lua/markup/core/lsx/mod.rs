mod props;

use core::fmt;
use std::rc::Rc;

pub use props::*;

use mlua::prelude::*;
use serde::Serialize;

#[derive(Debug)]
pub struct Element {
    pub kind: ElementKind,
    pub props: PendingProps,
    pub key: Option<String>,
}

impl Element {
    pub fn new(kind: ElementKind, props: PendingProps, key: Option<String>) -> Self {
        Element { kind, props, key }
    }
}

impl FromLua for Element {
    fn from_lua(value: LuaValue, lua: &Lua) -> LuaResult<Self> {
        match value {
            LuaValue::Table(t) => {
                let kind: ElementKind = t.get("kind")?;
                let props: PendingProps = t.get("props")?;
                let key: Option<String> = t.get("key").ok();

                Ok(Element::new(kind, props, key))
            }
            _ => Err(LuaError::external("Expected LuaElement user data")),
        }
    }
}

#[derive(Debug, Default)]
pub enum ElementKind {
    Element(String), // represents a tag name like "div", "span", etc.
    Component(LuaRegistryKey),
    Fragment(LuaTable),
    #[default]
    Text,
}

impl FromLua for ElementKind {
    fn from_lua(value: LuaValue, lua: &Lua) -> LuaResult<Self> {
        match value {
            LuaValue::String(s) => Ok(ElementKind::Element(s.to_str()?.to_string())),
            LuaValue::Function(f) => {
                let key = lua.create_registry_value(f)?;
                Ok(ElementKind::Component(key))
            }
            LuaValue::Table(t) => {
                if t.is_empty() {
                    return Ok(ElementKind::Fragment(t));
                }
                Err(LuaError::external(
                    "Expected a string, function, or empty table for ElementKind",
                ))
            }
            _ => Err(LuaError::external(
                "Expected a string, function, or table for ElementKind",
            )),
        }
    }
}
