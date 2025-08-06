mod dom;
mod lsx;
mod reconciler;

pub mod prelude {
    pub use crate::dom::*;
    pub use crate::lsx::*;
    pub use crate::reconciler::*;
}

use crate::prelude::*;
use mlua::prelude::*;
use std::{cell::RefCell, rc::Rc};
pub use taffy::prelude::*;

pub fn create_dom(_: &Lua, _: ()) -> LuaResult<LuaDom> {
    Ok(LuaDom(Rc::new(RefCell::new(Dom::new()))))
}

pub fn create_element(
    _: &Lua,
    (kind, props, key): (ElementKind, ElementProps, Option<String>),
) -> LuaResult<LuaElement> {
    let lsx = Element::new(kind, props, key);
    Ok(LuaElement::new(lsx))
}

// pub fn create_text_node(_: &Lua, text: String) -> LuaResult<LuaElement> {
//     let text_node = Element::new()
//     Ok(LuaTextNode::new(text_node))
// }

// NOTE: skip_memory_check greatly improves performance
// https://github.com/mlua-rs/mlua/issues/318
#[mlua::lua_module(skip_memory_check)]
fn markup_module(lua: &Lua) -> LuaResult<LuaTable> {
    let exports = lua.create_table()?;

    exports.set("create_dom", lua.create_function(create_dom)?)?;
    exports.set("create_lsx", lua.create_function(create_element)?)?;

    Ok(exports)
}
