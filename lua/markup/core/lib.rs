// mod dom;
mod lsx;
mod reconciler;
mod util;

pub mod prelude {
    // pub use crate::dom::*;
    pub use crate::lsx::*;
    pub use crate::reconciler::*;
}

use crate::prelude::*;
use mlua::prelude::*;
use std::{cell::RefCell, rc::Rc};
pub use taffy::prelude::*;

// creates a new LuaDom instance which can be used to create nodes
// pub fn create_dom(_: &Lua, _: ()) -> LuaResult<LuaDom> {
//     Ok(LuaDom(Rc::new(RefCell::new(Dom::new()))))
// }

// NOTE: skip_memory_check greatly improves performance
// https://github.com/mlua-rs/mlua/issues/318
#[mlua::lua_module(skip_memory_check)]
fn markup_core(lua: &Lua) -> LuaResult<LuaTable> {
    let exports = lua.create_table()?;

    // exports.set("create_dom", lua.create_function(create_dom)?)?;
    // exports.set("render", lua.create_function(create_element)?)?;

    Ok(exports)
}
