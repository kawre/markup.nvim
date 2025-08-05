mod print;
pub mod traits;
pub mod tree;

use std::{cell::RefCell, rc::Rc};

use mlua::prelude::*;
use taffy::Style;
pub use traits::*;
pub use tree::*;

use crate::{
    compute::{TextChunk, TextContext, WritingMode},
    node::{LuaNode, LuaProps, Node},
};

/// LuaTree is a Lua user data type that wraps the Tree structure.
pub struct LuaTree(pub Rc<RefCell<Tree>>);

impl LuaUserData for LuaTree {
    fn add_methods<M: mlua::UserDataMethods<Self>>(methods: &mut M) {
        methods.add_method_mut(
            "create_element",
            |lua, this, (kind_str, props_value): (String, Option<LuaValue>)| {
                let props_table: LuaTable = match props_value {
                    Some(LuaValue::Table(table)) => table,
                    Some(LuaValue::Nil) | None => lua.create_table()?,
                    _ => return Err(mlua::Error::external("Expected table or nil for props")),
                };
                let lua_props = LuaProps::new(props_table);

                let style: Style = lua_props.to_style();
                let mut node = Node::new_from_kind_str(kind_str, style);
                if let Some(highlight) = lua_props.get_prop("highlight") {
                    node.highlight = highlight.to_string().ok();
                }
                let node_id = this.0.borrow_mut().add_node(node);

                let lua_node = LuaNode::new(this.0.clone(), node_id);
                Ok(lua_node)
            },
        );
        methods.add_method_mut("create_text_node", |_, this, chunks_table: LuaTable| {
            // lua sends a table of chunks { chunk = "...", display_width: n }
            let chunks: Vec<TextChunk> = chunks_table
                .sequence_values::<LuaTable>()
                .map(|pair| {
                    let chunk = pair?;
                    let text: String = chunk.get("chunk")?;
                    let width: i32 = chunk.get("display_width")?;
                    Ok(TextChunk {
                        text_content: text,
                        display_width: width,
                    })
                })
                .collect::<LuaResult<Vec<TextChunk>>>()?;

            let node = Node::new_text(TextContext {
                chunks,
                writing_mode: WritingMode::Horizontal,
            });
            let node_id = this.0.borrow_mut().add_node(node);

            let lua_node = LuaNode::new(this.0.clone(), node_id);
            Ok(lua_node)
        });
    }
}
