use crate::prelude::*;
use mlua::prelude::*;
use std::{cell::RefCell, rc::Rc, str::FromStr};
use taffy::Style;

/// LuaTree is a Lua user data type that wraps the Tree structure.
pub struct LuaDom(pub Rc<RefCell<Dom>>);

impl LuaUserData for LuaDom {
    fn add_methods<M: mlua::UserDataMethods<Self>>(methods: &mut M) {
        methods.add_method_mut(
            "create_element",
            |_, this, (kind_str, props): (String, Option<ElementProps>)| {
                let node = Node::from_str(&kind_str)?;
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
