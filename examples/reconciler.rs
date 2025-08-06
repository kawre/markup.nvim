use std::{cell::RefCell, rc::Rc};

use markup::prelude::*;
use mlua::prelude::*;

pub fn create_lsx(_: &Lua, (kind, props): (LsxKind, Option<LuaProps>)) -> LuaResult<LuaLsx> {
    let lsx = Lsx::new(kind, props);
    Ok(LuaLsx::new(lsx))
}

fn main() -> LuaResult<()> {
    let lua = Lua::new();

    // Define a Rust function/closure
    let rust_func = lua.create_function(create_lsx)?;
    lua.globals().set("create_lsx", rust_func)?;

    // let bo: LuaValue = lua.load("return false").eval()?;
    // let xd = LuaPropsChild::from_lua(bo.clone(), &lua)?;

    let res: LuaLsx = lua
        .load(
            r#"
        local lsx = create_lsx("inline", {
            width = 100,
            children = { 1, false },
        })
        return lsx
        "#,
        )
        .eval()?;

    let fiber_ref = Fiber::from(res).into_ref();

    reconcile(fiber_ref);

    Ok(())
}
