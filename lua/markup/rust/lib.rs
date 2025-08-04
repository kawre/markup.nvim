mod compute;
mod node;
mod style;
mod tree;

use crate::tree::{LuaTree, Tree};
use mlua::prelude::*;
use std::{cell::RefCell, rc::Rc};
pub use taffy::prelude::*;

pub fn create_dom(_: &Lua, _: ()) -> LuaResult<LuaTree> {
    Ok(LuaTree(Rc::new(RefCell::new(Tree::new()))))
}

// NOTE: skip_memory_check greatly improves performance
// https://github.com/mlua-rs/mlua/issues/318
#[mlua::lua_module(skip_memory_check)]
fn markup_module(lua: &Lua) -> LuaResult<LuaTable> {
    let exports = lua.create_table()?;

    exports.set("create_dom", lua.create_function(create_dom)?)?;

    Ok(exports)
}
