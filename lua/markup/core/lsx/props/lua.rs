use crate::prelude::*;
use mlua::prelude::*;
use std::rc::Rc;

// Helper to convert LuaValue to text string for ElementChild/ElementChildren
fn lua_value_to_text(value: &LuaValue) -> Option<String> {
    match value {
        LuaValue::Boolean(true) => Some("true".to_string()),
        LuaValue::String(s) => s.to_str().ok().map(|s| s.to_string()),
        LuaValue::Integer(i) => Some(i.to_string()),
        LuaValue::Number(n) => Some(n.to_string()),
        _ => None,
    }
}

fn is_false_or_nil(val: &LuaValue) -> bool {
    matches!(val, LuaValue::Boolean(false) | LuaValue::Nil)
}

fn extract_children_sequence(table: &LuaTable, lua: &Lua) -> LuaResult<ElementChildren> {
    let seq: Vec<_> = (1..=table.raw_len())
        .filter_map(|i| {
            let value: LuaValue = table.raw_get(i).ok()?;
            if is_false_or_nil(&value) {
                None
            } else {
                ElementChild::from_lua(value, lua).ok()
            }
        })
        .collect();

    match seq.len() {
        0 => Ok(ElementChildren::None),
        1 => Ok(ElementChildren::from_child(seq.into_iter().next().unwrap())),
        _ => Ok(ElementChildren::Sequence(seq)),
    }
}

impl FromLua for PendingProps {
    fn from_lua(value: LuaValue, lua: &Lua) -> LuaResult<Self> {
        match value {
            LuaValue::Boolean(false) | LuaValue::Nil => Ok(Self::default()),
            LuaValue::UserData(ud) => {
                let parsed = ud.borrow::<LuaElement>()?;
                let element_child = ElementChild::Element(Rc::clone(&parsed.0));

                Ok(Self {
                    base: None,
                    children: ElementChildren::from_child(element_child),
                })
            }
            LuaValue::Table(t) => {
                // Check if it already has "children" key
                let has_children_key: bool = t.contains_key("children")?;

                if has_children_key {
                    let children_value: LuaValue = t.get("children")?;

                    if is_false_or_nil(&children_value) {
                        return Ok(Self::default());
                    } else {
                        let children = ElementChildren::from_lua(children_value, lua)?;
                        return Ok(Self {
                            base: Some(t),
                            children,
                        });
                    }
                }

                // Otherwise, collect numbered keys as children
                let mut children_list = Vec::new();

                for pair in t.pairs::<LuaValue, LuaValue>() {
                    let (key, value) = pair?;

                    if let LuaValue::Integer(_) = key {
                        if !is_false_or_nil(&value) {
                            let child = ElementChild::from_lua(value, lua)?;
                            children_list.push(child);
                        }
                    }
                }

                Ok(match children_list.len() {
                    0 => Self {
                        base: Some(t),
                        children: ElementChildren::None,
                    },
                    1 => Self {
                        base: Some(t),
                        children: ElementChildren::from_child(children_list.remove(0)),
                    },
                    _ => Self {
                        base: Some(t),
                        children: ElementChildren::Sequence(children_list),
                    },
                })
            }
            value => match lua_value_to_text(&value) {
                Some(text) => Ok(PendingProps {
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

impl FromLua for ElementChildren {
    fn from_lua(value: LuaValue, lua: &Lua) -> LuaResult<ElementChildren> {
        match value {
            LuaValue::Table(t) => extract_children_sequence(&t, lua),
            value => match lua_value_to_text(&value) {
                Some(text) => Ok(ElementChildren::Text(text)),
                _ => Err(mlua::Error::external(
                    "Expected a table, string, number, or boolean for ElementChildren",
                )),
            },
        }
    }
}

impl FromLua for ElementChild {
    fn from_lua(value: LuaValue, _: &Lua) -> LuaResult<ElementChild> {
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
}
