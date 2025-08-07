use crate::prelude::*;
use mlua::prelude::*;
use std::str::FromStr;
use taffy::prelude::*;

/// LuaTree is a Lua user data type that wraps the Tree structure.
pub struct LuaDom(pub DomRef);

impl LuaUserData for LuaDom {
    fn add_methods<M: mlua::UserDataMethods<Self>>(methods: &mut M) {
        methods.add_method_mut("create_element", |_, this, kind_str: String| {
            let node = Node::from_str(&kind_str)?;
            let node_id = this.0.borrow_mut().add_node(node);
            let lua_node = LuaNode::new(this.0.clone(), node_id);
            Ok(lua_node)
        });
        methods.add_method_mut("create_text_node", |_, this, chunks: TextChunks| {
            let node = Node::new_text(TextContext {
                chunks: chunks.0,
                writing_mode: WritingMode::Horizontal,
            });
            let node_id = this.0.borrow_mut().add_node(node);
            let lua_node = LuaNode::new(this.0.clone(), node_id);
            Ok(lua_node)
        });
    }
}
