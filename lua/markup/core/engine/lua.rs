//! The engine as a Lua userdata.

use super::Engine;
use super::protocol;
use mlua::prelude::*;

pub struct LuaEngine(Engine);

pub fn create_engine(_: &Lua, width: i32) -> LuaResult<LuaEngine> {
    Ok(LuaEngine(Engine::new(width)))
}

impl LuaUserData for LuaEngine {
    fn add_methods<M: LuaUserDataMethods<Self>>(methods: &mut M) {
        // Applies `len` values of commands and returns the resulting frame.
        methods.add_method_mut("commit", |lua, this, (ops, len): (LuaTable, usize)| {
            protocol::decode(&ops, len, |command| {
                this.0.apply(command).map_err(|error| LuaError::runtime(error.to_string()))
            })?;
            this.0.render(|patches, timings| protocol::encode(lua, patches, timings))
        });

        // Zero indexed cell to the innermost interactive node, if any.
        methods.add_method("node_at", |_, this, (row, col): (i32, i32)| Ok(this.0.node_at(row, col)));

        methods.add_method("node_count", |_, this, ()| Ok(this.0.tree().len()));
    }
}
