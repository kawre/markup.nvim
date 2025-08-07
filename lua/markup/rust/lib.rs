mod dom;
mod lsx;
mod reconciler;
mod util;

pub mod prelude {
    pub use crate::dom::*;
    pub use crate::lsx::*;
    pub use crate::reconciler::*;
}

use crate::prelude::*;
use mlua::prelude::*;
use std::{cell::RefCell, rc::Rc};
pub use taffy::prelude::*;

// creates a new LuaDom instance which can be used to create nodes
pub fn create_dom(_: &Lua, _: ()) -> LuaResult<LuaDom> {
    Ok(LuaDom(Rc::new(RefCell::new(Dom::new()))))
}

// creates lsx-like elements
pub fn create_element(
    _: &Lua,
    (kind, props, key): (ElementKind, ElementProps, Option<String>),
) -> LuaResult<LuaElement> {
    let lsx = Element::new(kind, props, key);
    Ok(LuaElement::from(lsx))
}

// pub fn print_props(lua: &Lua, props: ElementProps) -> LuaResult<String> {
//     // let style = Style::from(props);
//     let style: Style = Style::try_from(props)?;
//     let json_str = serde_json::to_string_pretty(&style).unwrap();
//
//     Ok(json_str)
// }

// NOTE: skip_memory_check greatly improves performance
// https://github.com/mlua-rs/mlua/issues/318
#[mlua::lua_module(skip_memory_check)]
fn markup_module(lua: &Lua) -> LuaResult<LuaTable> {
    let exports = lua.create_table()?;

    exports.set("create_dom", lua.create_function(create_dom)?)?;
    exports.set("create_lsx", lua.create_function(create_element)?)?;
    // exports.set("print_props", lua.create_function(print_props)?)?;
    // exports.set("reconcile", lua.create_function(lua_reconcile)?)?;

    Ok(exports)
}
