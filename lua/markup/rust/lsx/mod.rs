mod lua;
mod props;

use core::fmt;
use std::rc::Rc;

pub use lua::*;
pub use props::*;

use mlua::prelude::*;

#[derive(Debug, Clone)]
pub struct Element {
    pub kind: ElementKind,
    pub props: ElementProps,
    pub key: Option<String>,
}

pub type ElementRef = Rc<Element>;

impl Element {
    pub fn new(kind: ElementKind, props: ElementProps, key: Option<String>) -> Self {
        Element { kind, props, key }
    }
}

impl From<LuaElement> for Element {
    fn from(lua_lsx: LuaElement) -> Self {
        (*lua_lsx.0).clone()
    }
}

impl From<String> for Element {
    fn from(text: String) -> Self {
        Element {
            kind: ElementKind::Text,
            props: ElementProps::from(text),
            key: None,
        }
    }
}

#[derive(Debug, Clone)]
pub enum ElementKind {
    Element(String),
    Component(LuaFunction),
    Fragment(LuaTable),
    Text,
}

impl fmt::Display for ElementKind {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            ElementKind::Element(name) => write!(f, "Element({})", name),
            ElementKind::Component(_) => write!(f, "Component(<LuaFunction>)"),
            ElementKind::Fragment(_) => write!(f, "Fragment(<LuaTable>)"),
            ElementKind::Text => write!(f, "Text"),
        }
    }
}
