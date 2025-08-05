mod lua;
mod props;

pub use lua::*;
pub use props::*;

use mlua::prelude::*;

#[derive(Debug, Clone, Default)]
pub struct Lsx {
    pub kind: LsxKind,
    pub props: Option<LuaProps>,
}

#[derive(Debug, Clone)]
pub enum LsxKind {
    Element(LuaLsx),
    Text(String),
    Component(LuaFunction),
    // Fragment(LuaTable),
}

impl Default for LsxKind {
    fn default() -> Self {
        LsxKind::Text(String::new())
    }
}

impl Lsx {
    pub fn new(kind: LsxKind, props: Option<LuaProps>) -> Self {
        Lsx { kind, props }
    }
}

impl FromLua for LsxKind {
    fn from_lua(value: LuaValue, _: &Lua) -> LuaResult<Self> {
        match value {
            LuaValue::Function(f) => Ok(LsxKind::Component(f)),
            LuaValue::String(s) => Ok(LsxKind::Text(s.to_str()?.to_string())),
            LuaValue::UserData(ud) => {
                if let Ok(lsx_ref) = ud.borrow::<LuaLsx>() {
                    Ok(LsxKind::Element(lsx_ref.clone()))
                } else {
                    Err(LuaError::external("Expected LuaLsx user data"))
                }
            }
            _ => Err(LuaError::external("Invalid LsxKind type")),
        }
    }
}

impl IntoLua for LsxKind {
    fn into_lua(self, lua: &Lua) -> LuaResult<LuaValue> {
        match self {
            LsxKind::Element(lsx) => Ok(LuaValue::UserData(lua.create_userdata(lsx)?)),
            LsxKind::Text(text) => Ok(LuaValue::String(lua.create_string(&text)?)),
            LsxKind::Component(func) => Ok(LuaValue::Function(func)),
        }
    }
}
