mod lua;

pub use lua::*;

use crate::prelude::*;
use mlua::prelude::*;

#[derive(Debug, Clone, Default)]
pub struct ElementProps {
    base: Option<LuaTable>, // keep for later to extract properties during node creation
    pub children: ElementChildren,
}

impl From<String> for ElementProps {
    fn from(text: String) -> Self {
        ElementProps {
            children: ElementChildren::Text(text),
            ..Default::default()
        }
    }
}

#[derive(Debug, Clone, Default)]
pub enum ElementChildren {
    #[default]
    None,
    Text(String),
    Sequence(Vec<ElementChild>),
}

#[derive(Debug, Clone)]
pub enum ElementChild {
    Text(String),
    Element(ElementRef),
    Table(LuaTable),
}

impl ElementChildren {
    pub fn from_child(child: ElementChild) -> Self {
        match child {
            ElementChild::Text(s) => ElementChildren::Text(s),
            _ => ElementChildren::Sequence(vec![child]),
        }
    }
}

impl PartialEq for ElementProps {
    fn eq(&self, other: &Self) -> bool {
        match (&self.base, &other.base) {
            (Some(b1), Some(b2)) => b1.to_pointer() == b2.to_pointer(),
            _ => true,
        }
    }
}
