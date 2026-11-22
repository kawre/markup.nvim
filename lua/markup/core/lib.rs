//! Native core of markup.nvim.
//!
//! Lua owns reactivity and everything that talks to Neovim. This crate owns the
//! retained node tree and turns it into line patches:
//!
//! ```text
//! commands -> tree -> layout -> paint -> diff -> patches
//! ```
//!
//! Only `engine::protocol` and `engine::lua` know about Lua. No Lua handle is
//! stored between calls, so the tree is plain data and mlua's limit of roughly
//! 8000 live handles under LuaJIT cannot be reached.

pub mod engine;
pub mod matcher;

// Neovim provides the Lua symbols at runtime, only test binaries need them linked.
#[cfg(test)]
#[link(name = "luajit-5.1")]
unsafe extern "C" {}

use mlua::prelude::*;

// NOTE: skip_memory_check greatly improves performance
// https://github.com/mlua-rs/mlua/issues/318
#[mlua::lua_module(skip_memory_check)]
fn markup_core(lua: &Lua) -> LuaResult<LuaTable> {
    let exports = lua.create_table()?;
    // The version this engine was built as, to tell whether it is the one the
    // Lua side expects.
    exports.set("version", env!("CARGO_PKG_VERSION"))?;
    exports.set("overflow_marker", true)?;
    exports.set(
        "create_engine",
        lua.create_function(engine::lua::create_engine)?,
    )?;
    exports.set(
        "create_matcher",
        lua.create_function(matcher::create_matcher)?,
    )?;
    Ok(exports)
}
