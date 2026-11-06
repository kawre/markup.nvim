//! The engine as a Lua userdata.

use super::Engine;
use super::protocol;
use super::tree::{ClientId, TreeError};
use mlua::prelude::*;

pub struct LuaEngine(Engine);

fn to_lua_error(error: TreeError) -> LuaError {
    LuaError::runtime(error.to_string())
}

pub fn create_engine(_: &Lua, width: i32) -> LuaResult<LuaEngine> {
    Ok(LuaEngine(Engine::new(width)))
}

impl LuaUserData for LuaEngine {
    fn add_methods<M: LuaUserDataMethods<Self>>(methods: &mut M) {
        // Applies `len` values of commands and returns the resulting frame.
        methods.add_method_mut("commit", |lua, this, (ops, len): (LuaTable, usize)| {
            protocol::decode(&ops, len, |command| {
                this.0.apply(command).map_err(to_lua_error)
            })?;
            this.0.render(|patches, timings| protocol::encode(lua, patches, timings))
        });

        // Zero indexed cell to the innermost interactive node, if any.
        methods.add_method("node_at", |_, this, (row, col): (i32, i32)| Ok(this.0.node_at(row, col)));

        methods.add_method("node_count", |_, this, ()| Ok(this.0.tree().len()));

        methods.add_method_mut("reset_frame", |_, this, ()| {
            this.0.reset_frame();
            Ok(())
        });

        // Zero indexed cells. Returns the row and column to move to, if any.
        methods.add_method(
            "snap",
            |_, this, (from_row, from_col, row, col): (i32, i32, i32, i32)| {
                Ok(this.0.snap((from_row, from_col), (row, col)).unzip())
            },
        );

        // Devtools, see `engine::inspect`.
        methods.add_method("path_at", |_, this, (row, col): (i32, i32)| {
            Ok(this.0.path_at(row, col))
        });

        methods.add_method("describe", |lua, this, id: ClientId| {
            let info = this.0.describe(id).map_err(to_lua_error)?;
            protocol::encode_node(lua, &info)
        });

        methods.add_method(
            "children",
            |lua, this, (id, offset, limit, flatten): (ClientId, usize, usize, bool)| {
                let (total, page) = this
                    .0
                    .children_of(id, offset, limit, flatten)
                    .map_err(to_lua_error)?;
                let nodes = lua.create_table_with_capacity(page.len(), 1)?;
                for (index, info) in page.iter().enumerate() {
                    nodes.raw_set(index + 1, protocol::encode_node(lua, info)?)?;
                }
                nodes.raw_set("total", total)?;
                Ok(nodes)
            },
        );

        methods.add_method("child_position", |_, this, (id, flatten): (ClientId, bool)| {
            this.0.child_position(id, flatten).map_err(to_lua_error)
        });
    }
}
