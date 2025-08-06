use mlua::prelude::*;
use std::rc::Rc;

use crate::prelude::*;

#[derive(Debug, Clone)]
pub struct LuaElement(pub Rc<Element>);

impl LuaElement {
    pub fn new(lsx: Element) -> Self {
        LuaElement(Rc::new(lsx))
    }
}

impl FromLua for LuaElement {
    fn from_lua(value: LuaValue, _: &Lua) -> LuaResult<Self> {
        match value {
            LuaValue::UserData(ud) => ud.borrow::<LuaElement>().map(|r| r.clone()),
            _ => Err(LuaError::external("Expected LuaLsx user data")),
        }
    }
}

impl LuaUserData for LuaElement {
    fn add_fields<F: LuaUserDataFields<Self>>(fields: &mut F) {
        fields.add_field_method_get("kind", |_, this| Ok(this.0.kind.clone()));
        // fields.add_field_method_get("props", |_, this| Ok(this.props.clone()));
    }

    fn add_methods<M: LuaUserDataMethods<Self>>(methods: &mut M) {
        methods.add_meta_method(LuaMetaMethod::ToString, |_, this, ()| {
            let kind_str = this.0.kind.to_string();

            match this.0.props.children.clone() {
                ElementChildren::None => Ok(kind_str),
                ElementChildren::Text(text) => Ok(format!("{}: #[{}]", kind_str, text)),
                ElementChildren::Sequence(children) => {
                    let children_str: Vec<String> = children
                        .iter()
                        .map(|child| match child {
                            ElementChild::Element(e) => e.kind.to_string(),
                            ElementChild::Text(t) => t.into(),
                            _ => "Unknown".to_string(),
                        })
                        .collect();
                    Ok(format!("{}:\n - {}", kind_str, children_str.join("\n - ")))
                }
            }
        });
    }
}

impl FromLua for ElementKind {
    fn from_lua(value: LuaValue, _: &Lua) -> LuaResult<Self> {
        match value {
            LuaValue::Function(f) => Ok(ElementKind::Component(f)),
            LuaValue::String(s) => Ok(ElementKind::Element(s.to_str()?.to_string())),
            LuaValue::Table(t) => Ok(ElementKind::Fragment(t)),
            _ => Err(LuaError::external("Invalid ElementKind type")),
        }
    }
}

impl IntoLua for ElementKind {
    fn into_lua(self, lua: &Lua) -> LuaResult<LuaValue> {
        match self {
            // LsxKind::Element(lsx) => Ok(LuaValue::UserData(lua.create_userdata(lsx)?)),
            ElementKind::Element(text) => Ok(LuaValue::String(lua.create_string(&text)?)),
            ElementKind::Component(func) => Ok(LuaValue::Function(func)),
            ElementKind::Fragment(table) => Ok(LuaValue::Table(table)),
            ElementKind::Text => Ok(LuaValue::String(lua.create_string("text")?)),
        }
    }
}
