mod props;

use crate::prelude::*;
use mlua::prelude::*;
pub use props::*;

#[derive(Debug)]
pub struct Element {
    pub kind: ElementKind,
    pub key: Option<String>,
}

pub struct ElementProps {}

#[derive(Debug)]
pub enum ElementKind {
    Element(String, LuaRegistryKey), // (tag, props)
    Component(LuaRegistryKey),       // component function
    Fragment(LuaRegistryKey),        // fragment table
    Text(String),                    // text content
}

impl FromLua for Element {
    fn from_lua(value: LuaValue, lua: &Lua) -> LuaResult<Self> {
        match value {
            LuaValue::Table(t) => {
                let kind: LuaValue = t.get("kind")?;
                let key: Option<String> = t.get("key")?;

                match kind {
                    LuaValue::String(s) => {
                        let props: LuaValue = t.get("props")?;

                        match props {
                            LuaValue::String(str) => Ok(Element {
                                kind: ElementKind::Text(str.to_str()?.to_string()),
                                key,
                            }),
                            LuaValue::Table(props) => {
                                let rkey = lua
                                    .create_registry_value(&props)
                                    .expect("Failed to create registry value for props");
                                Ok(Element {
                                    kind: ElementKind::Element(s.to_str()?.to_string(), rkey),
                                    key,
                                })
                            }
                            _ => Err(LuaError::external(
                                "Expected a string or table for Element props",
                            )),
                        }
                    }
                    LuaValue::Table(t) => {
                        let rkey = lua
                            .create_registry_value(t)
                            .expect("Failed to create registry value for fragment");

                        Ok(Element {
                            kind: ElementKind::Fragment(rkey),
                            key,
                        })
                    }
                    LuaValue::Function(f) => {
                        let rkey = lua
                            .create_registry_value(f)
                            .expect("Failed to create registry value for component");

                        Ok(Element {
                            kind: ElementKind::Component(rkey),
                            key,
                        })
                    }
                    _ => Err(LuaError::external(
                        "Expected a string or function for Element kind",
                    )),
                }
            }
            _ => Err(LuaError::external("Expected LuaElement user data")),
        }
    }
}

impl PartialEq<FiberKind> for ElementKind {
    fn eq(&self, other: &FiberKind) -> bool {
        match (self, other) {
            (ElementKind::Element(tag, _), FiberKind::Element(ef)) => ef.element_tag == *tag,
            (ElementKind::Text(text), FiberKind::Text(t)) => t == text,
            (ElementKind::Component(_), FiberKind::Function(_)) => true,
            (ElementKind::Fragment(_), FiberKind::Fragment(_)) => true,
            _ => false,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn create_element(lua: &Lua, (kind, props): (String, LuaValue)) -> LuaResult<LuaTable> {
        let metatable = lua.create_table()?;
        metatable.set("__type", "markup.element")?;
        let el = lua.create_table()?;
        el.set_metatable(Some(metatable))?;

        el.set("kind", kind)?;
        el.set("props", props)?;

        Ok(el)
    }

    fn setup_lua() -> LuaResult<Lua> {
        let lua = Lua::new();
        lua.globals()
            .set("create_lsx", lua.create_function(create_element)?)?;
        Ok(lua)
    }

    #[test]
    fn test_element_kind_text_creation() {
        let lua = setup_lua().unwrap();

        let text_res: LuaValue = lua
            .load(
                r#"
                return create_lsx("text", "Hello World")
                "#,
            )
            .eval()
            .unwrap();

        let text_element = Element::from_lua(text_res, &lua).unwrap();

        match text_element.kind {
            ElementKind::Text(content) => {
                assert_eq!(content, "Hello World");
            }
            _ => panic!("Expected ElementKind::Text, got {:?}", text_element.kind),
        }

        assert!(text_element.key.is_none());
    }

    #[test]
    fn test_element_kind_text_empty_string() {
        let lua = setup_lua().unwrap();

        let empty_text_res: LuaValue = lua
            .load(
                r#"
                return create_lsx("text", "")
                "#,
            )
            .eval()
            .unwrap();

        let empty_text_element = Element::from_lua(empty_text_res, &lua).unwrap();

        match empty_text_element.kind {
            ElementKind::Text(content) => {
                assert_eq!(content, "");
            }
            _ => panic!(
                "Expected ElementKind::Text, got {:?}",
                empty_text_element.kind
            ),
        }
    }

    #[test]
    fn test_element_kind_element_with_table_props() {
        let lua = setup_lua().unwrap();

        let element_res: LuaValue = lua
            .load(
                r#"
                return create_lsx("div", {
                    id = "test-id",
                    class = "container",
                    children = { "Hello", "World" }
                })
                "#,
            )
            .eval()
            .unwrap();

        let element_with_props = Element::from_lua(element_res, &lua).unwrap();

        match element_with_props.kind {
            ElementKind::Element(tag, registry_key) => {
                assert_eq!(tag, "div");

                // Verify we can retrieve the props from the registry
                let props: LuaTable = lua.registry_value(&registry_key).unwrap();
                let id: String = props.get("id").unwrap();
                let class: String = props.get("class").unwrap();

                assert_eq!(id, "test-id");
                assert_eq!(class, "container");
            }
            _ => panic!(
                "Expected ElementKind::Element, got {:?}",
                element_with_props.kind
            ),
        }

        assert!(element_with_props.key.is_none());
    }

    #[test]
    fn test_element_kind_element_with_key() {
        let lua = setup_lua().unwrap();

        let keyed_element_res: LuaValue = lua
            .load(
                r#"
                local el = create_lsx("span", { content = "test" })
                el.key = "unique-key"
                return el
                "#,
            )
            .eval()
            .unwrap();

        let keyed_element = Element::from_lua(keyed_element_res, &lua).unwrap();

        match keyed_element.kind {
            ElementKind::Element(tag, registry_key) => {
                assert_eq!(tag, "span");

                let props: LuaTable = lua.registry_value(&registry_key).unwrap();
                let content: String = props.get("content").unwrap();
                assert_eq!(content, "test");
            }
            _ => panic!(
                "Expected ElementKind::Element, got {:?}",
                keyed_element.kind
            ),
        }

        assert_eq!(keyed_element.key, Some("unique-key".to_string()));
    }

    #[test]
    fn test_element_kind_element_with_different_tags() {
        let lua = setup_lua().unwrap();

        let tags = vec!["div", "span", "p", "h1", "custom-component"];

        for tag in tags {
            let lua_code = format!(
                r#"
                return create_lsx("{}", {{ attr = "value" }})
                "#,
                tag
            );

            let element_res: LuaValue = lua.load(&lua_code).eval().unwrap();
            let element = Element::from_lua(element_res, &lua).unwrap();

            match element.kind {
                ElementKind::Element(element_tag, _) => {
                    assert_eq!(element_tag, tag);
                }
                _ => panic!("Expected ElementKind::Element for tag {}", tag),
            }
        }
    }

    #[test]
    fn test_element_kind_element_with_complex_props() {
        let lua = setup_lua().unwrap();

        let element_res: LuaValue = lua
            .load(
                r#"
                return create_lsx("section", {
                    id = "main-section",
                    class = "container fluid",
                    style = {
                        width = "100%",
                        height = "auto"
                    },
                    children = {
                        "Some text",
                        { tag = "nested", content = "element" }
                    },
                    onclick = function() return "handler" end
                })
                "#,
            )
            .eval()
            .unwrap();

        let element = Element::from_lua(element_res, &lua).unwrap();

        match element.kind {
            ElementKind::Element(tag, registry_key) => {
                assert_eq!(tag, "section");

                let props: LuaTable = lua.registry_value(&registry_key).unwrap();

                // Test string props
                let id: String = props.get("id").unwrap();
                let class: String = props.get("class").unwrap();
                assert_eq!(id, "main-section");
                assert_eq!(class, "container fluid");

                // Test nested table props
                let style: LuaTable = props.get("style").unwrap();
                let width: String = style.get("width").unwrap();
                assert_eq!(width, "100%");

                // Test array props
                let children: LuaTable = props.get("children").unwrap();
                let first_child: String = children.get(1).unwrap();
                assert_eq!(first_child, "Some text");

                // Test function props
                let onclick: LuaFunction = props.get("onclick").unwrap();
                let result: String = onclick.call(()).unwrap();
                assert_eq!(result, "handler");
            }
            _ => panic!("Expected ElementKind::Element, got {:?}", element.kind),
        }
    }
}
