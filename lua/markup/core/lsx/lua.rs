use mlua::prelude::*;
use std::rc::Rc;

use crate::prelude::*;

#[derive(Debug, Clone)]
pub struct LuaElement(pub Rc<Element>);

impl From<Element> for LuaElement {
    fn from(lsx: Element) -> Self {
        LuaElement(Rc::new(lsx))
    }
}

impl FromLua for LuaElement {
    fn from_lua(value: LuaValue, _: &Lua) -> LuaResult<Self> {
        match value {
            LuaValue::UserData(ud) => ud.borrow::<LuaElement>().map(|r| r.clone()),
            _ => Err(LuaError::external("Expected LuaLsx user data")),
        }
    }
}

impl LuaUserData for LuaElement {
    fn add_fields<F: LuaUserDataFields<Self>>(fields: &mut F) {
        fields.add_field_method_get("kind", |_, this| Ok(this.0.kind.clone()));
        // fields.add_field_method_get("props", |_, this| Ok(this.props.clone()));
    }

    fn add_methods<M: LuaUserDataMethods<Self>>(methods: &mut M) {
        methods.add_meta_method(LuaMetaMethod::ToString, |_, this, ()| {
            let mut out = String::new();

            fn print_rec(child: &ElementChild, indent: usize, out: &mut String) {
                match child {
                    ElementChild::Text(str) => {
                        out.push_str(&format!("{}#[{}]\n", " ".repeat(indent), str))
                    }
                    ElementChild::Element(el) => match el.props.children.clone() {
                        ElementChildren::Text(str) => {
                            out.push_str(&format!(
                                "{}{} #[{}]\n",
                                " ".repeat(indent),
                                el.kind,
                                str
                            ));
                        }
                        ElementChildren::Sequence(ref seq) => {
                            out.push_str(&format!("{}{}\n", " ".repeat(indent), el.kind));
                            for child in seq {
                                print_rec(child, indent + 2, out);
                            }
                        }
                        ElementChildren::None => {}
                    },
                    ElementChild::Table(tbl) => {}
                }
            }

            print_rec(&ElementChild::Element(Rc::clone(&this.0)), 0, &mut out);
            Ok(out)
        });
    }
}

impl FromLua for ElementKind {
    fn from_lua(value: LuaValue, _: &Lua) -> LuaResult<Self> {
        match value {
            LuaValue::Function(f) => Ok(ElementKind::Component(f)),
            LuaValue::String(s) => Ok(ElementKind::Element(s.to_str()?.to_string())),
            LuaValue::Table(t) => Ok(ElementKind::Fragment(t)),
            _ => Err(LuaError::external("Invalid ElementKind type")),
        }
    }
}

impl IntoLua for ElementKind {
    fn into_lua(self, lua: &Lua) -> LuaResult<LuaValue> {
        match self {
            // LsxKind::Element(lsx) => Ok(LuaValue::UserData(lua.create_userdata(lsx)?)),
            ElementKind::Element(text) => Ok(LuaValue::String(lua.create_string(&text)?)),
            ElementKind::Component(func) => Ok(LuaValue::Function(func)),
            ElementKind::Fragment(table) => Ok(LuaValue::Table(table)),
            ElementKind::Text => Ok(LuaValue::String(lua.create_string("text")?)),
        }
    }
}
