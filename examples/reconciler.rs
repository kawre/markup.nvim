use std::{cell::RefCell, rc::Rc};

use markup::prelude::*;
use mlua::prelude::*;

pub fn create_lsx(
    _: &Lua,
    (kind, props, key): (ElementKind, ElementProps, Option<String>),
) -> LuaResult<LuaElement> {
    let lsx = Element::new(kind, props, key);
    Ok(LuaElement::new(lsx))
}

fn main() -> LuaResult<()> {
    let lua = Lua::new();

    let rust_func = lua.create_function(create_lsx)?;
    lua.globals().set("create_lsx", rust_func)?;

    let res: LuaElement = lua
        .load(
            r#"
            return create_lsx("inline", create_lsx("i'm inline"))
        "#,
        )
        .eval()?;

    print!("Result: {:?}", res);

    Ok(())
}
