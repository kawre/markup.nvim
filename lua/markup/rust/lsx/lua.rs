use mlua::prelude::*;
use std::rc::Rc;

use crate::prelude::*;

#[derive(Debug, Clone)]
pub struct LuaLsx(pub Rc<Lsx>);

impl LuaLsx {
    pub fn new(lsx: Lsx) -> Self {
        LuaLsx(Rc::new(lsx))
    }
}

impl FromLua for LuaLsx {
    fn from_lua(value: LuaValue, _: &Lua) -> LuaResult<Self> {
        match value {
            LuaValue::UserData(ud) => ud.borrow::<LuaLsx>().map(|r| r.clone()),
            _ => Err(LuaError::external("Expected LuaLsx user data")),
        }
    }
}

impl LuaUserData for LuaLsx {
    fn add_fields<F: LuaUserDataFields<Self>>(fields: &mut F) {
        fields.add_field_method_get("kind", |_, this| Ok(this.0.kind.clone()));
        // fields.add_field_method_get("props", |_, this| Ok(this.props.clone()));
    }

    fn add_methods<M: LuaUserDataMethods<Self>>(methods: &mut M) {
        methods.add_meta_method(LuaMetaMethod::ToString, |_, this, ()| {
            Ok(format!("{:?}", this.0.props))
        });
    }
}
