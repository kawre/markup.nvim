use std::{cell::RefCell, rc::Rc};

use markup::prelude::*;
use mlua::prelude::*;
use taffy::Style;

pub fn create_lsx(
    _: &Lua,
    (kind, props, key): (ElementKind, ElementProps, Option<String>),
) -> LuaResult<LuaElement> {
    let lsx = Element::new(kind, props, key);
    Ok(LuaElement::from(lsx))
}

fn main() -> LuaResult<()> {
    let lua = Lua::new();

    let rust_func = lua.create_function(create_lsx)?;
    lua.globals().set("create_lsx", rust_func)?;

    let res: ElementProps = lua
        .load(
            r#"
            --return create_lsx("inline", { 1, 2, create_lsx("i'm inline", {1}) })
            -- return create_lsx("inline", {1, 2})
            return { display = "block", width = "auto" }
        "#,
        )
        .eval()?;

    let style: Style = Style::try_from(res.clone())?;
    print!("{}", serde_json::to_string_pretty(&style).unwrap());
    // let fiber = Fiber::from(&res);
    // let fiber_ref = fiber.into_ref();
    // reconcile(fiber_ref.clone());
    // let alterante = fiber_ref.borrow().alternate.clone().unwrap();
    // print!("{}", alterante.borrow().print_tree());

    Ok(())
}
