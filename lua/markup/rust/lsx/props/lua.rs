use crate::prelude::*;
use mlua::prelude::*;
use std::rc::Rc;

// Helper to convert LuaValue to text string for ElementChild/ElementChildren
fn lua_value_to_text(value: &LuaValue) -> Option<String> {
    match value {
        LuaValue::Boolean(true) => Some("true".to_string()),
        LuaValue::Boolean(false) | LuaValue::Nil => None, // Filter out false/nil
        LuaValue::String(s) => s.to_str().ok().map(|s| s.to_string()),
        LuaValue::Integer(i) => Some(i.to_string()),
        LuaValue::Number(n) => Some(n.to_string()),
        _ => None,
    }
}

impl FromLua for ElementProps {
    fn from_lua(value: LuaValue, lua: &Lua) -> LuaResult<Self> {
        match value {
            LuaValue::Boolean(false) | LuaValue::Nil => Ok(ElementProps {
                base: None,
                children: ElementChildren::None,
            }),
            LuaValue::UserData(ud) => {
                let parsed = ud.borrow::<LuaElement>()?;
                let element_child = ElementChild::Element(Rc::clone(&parsed.0));

                Ok(ElementProps {
                    base: None,
                    children: ElementChildren::from_child(element_child),
                })
            }
            LuaValue::Table(t) => {
                // Check if it already has "children" key
                let has_children_key: bool = t.contains_key("children")?;
                if has_children_key {
                    let children_value: LuaValue = t.get("children")?;
                    let children = parse_children(children_value, lua)?;
                    return Ok(ElementProps {
                        base: Some(t),
                        children,
                    });
                }

                // Otherwise, collect numbered keys as children
                let mut children_list = Vec::new();
                for pair in t.pairs::<LuaValue, LuaValue>() {
                    let (key, value) = pair?;

                    if let LuaValue::Integer(_) = key {
                        children_list.push(parse_child(value, lua)?);
                    }
                }

                let children = match children_list.len() {
                    0 => ElementChildren::None,
                    1 => ElementChildren::from_child(children_list.remove(0)),
                    _ => ElementChildren::Sequence(children_list),
                };

                Ok(ElementProps {
                    base: Some(t),
                    children,
                })
            }
            value => match lua_value_to_text(&value) {
                Some(text) => Ok(ElementProps {
                    base: None,
                    children: ElementChildren::Text(text),
                }),
                _ => Err(mlua::Error::external(
                    "Expected a table, string, number, or boolean for ElementProps",
                )),
            },
        }
    }
}

fn parse_children(value: LuaValue, lua: &Lua) -> LuaResult<ElementChildren> {
    match value {
        LuaValue::Table(t) => {
            let len = t.raw_len();
            if len == 0 {
                // Probably a map, not a sequence
                Ok(ElementChildren::None)
            } else if len == 1 {
                let single: LuaValue = t.raw_get(1)?;
                let child = parse_child(single, lua)?;
                Ok(ElementChildren::from_child(child))
            } else {
                let mut seq = Vec::new();
                for i in 1..=len {
                    let v: LuaValue = t.raw_get(i)?;
                    seq.push(parse_child(v, lua)?);
                }
                Ok(ElementChildren::Sequence(seq))
            }
        }
        value => match lua_value_to_text(&value) {
            Some(text) => Ok(ElementChildren::Text(text)),
            _ => Err(mlua::Error::external(
                "Expected a table, string, number, or boolean for ElementChildren",
            )),
        },
    }
}

fn parse_child(value: LuaValue, _: &Lua) -> LuaResult<ElementChild> {
    match value {
        LuaValue::Table(t) => Ok(ElementChild::Table(t)),
        LuaValue::UserData(ud) => {
            if let Ok(el) = ud.borrow::<LuaElement>() {
                Ok(ElementChild::Element(Rc::clone(&el.0)))
            } else {
                Err(mlua::Error::external("Expected LuaLsx user data"))
            }
        }
        value => match lua_value_to_text(&value) {
            Some(text) => Ok(ElementChild::Text(text)),
            _ => Err(mlua::Error::external(
                "Expected a table, string, number, or boolean for ElementChild",
            )),
        },
    }
}
