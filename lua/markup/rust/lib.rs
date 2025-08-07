// mod dom;
mod lsx;
// mod reconciler;
mod util;

pub mod prelude {
    // pub use crate::dom::*;
    pub use crate::lsx::*;
    // pub use crate::reconciler::*;
}

use crate::prelude::*;
use mlua::{LuaSerdeExt, prelude::*};
use std::{cell::RefCell, rc::Rc};
pub use taffy::prelude::*;

// pub fn create_dom(_: &Lua, _: ()) -> LuaResult<LuaDom> {
//     Ok(LuaDom(Rc::new(RefCell::new(Dom::new()))))
// }

pub fn create_element(
    _: &Lua,
    (kind, props, key): (ElementKind, ElementProps, Option<String>),
) -> LuaResult<LuaElement> {
    let style: Style = Style::try_from(props.clone())?;

    let pretty = format!("{:?}", style);
    println!("{}", pretty);

    let lsx = Element::new(kind, props, key);

    Ok(LuaElement::new(lsx))
}

pub fn print_props(lua: &Lua, props: ElementProps) -> LuaResult<String> {
    // let style = Style::from(props);
    let style: Style = Style::try_from(props)?;
    let json_str = serde_json::to_string_pretty(&style).unwrap();

    Ok(json_str)
}

// pub fn lua_reconcile(_: &Lua, element: LuaElement) -> LuaResult<String> {
//     let fiber = Fiber::from(&element);
//     let fiber_ref = fiber.into_ref();
//     reconcile(fiber_ref.clone());
//     let alterante = fiber_ref.borrow().alternate.clone().unwrap();
//     Ok(alterante.borrow().print_tree())
// }

// pub fn create_text_node(_: &Lua, text: String) -> LuaResult<LuaElement> {
//     let text_node = Element::new()
//     Ok(LuaTextNode::new(text_node))
// }

// NOTE: skip_memory_check greatly improves performance
// https://github.com/mlua-rs/mlua/issues/318
#[mlua::lua_module(skip_memory_check)]
fn markup_module(lua: &Lua) -> LuaResult<LuaTable> {
    let exports = lua.create_table()?;

    // exports.set("create_dom", lua.create_function(create_dom)?)?;
    exports.set("create_lsx", lua.create_function(create_element)?)?;
    exports.set("print_props", lua.create_function(print_props)?)?;
    // exports.set("reconcile", lua.create_function(lua_reconcile)?)?;

    Ok(exports)
}
