use crate::{prelude::*, util};
use mlua::prelude::*;
use std::cell::RefCell;
use std::future::pending;
use std::rc::Rc;

type RootProps = Rc<LuaRegistryKey>;
type FunctionProps = Rc<LuaRegistryKey>;

#[derive(Debug)]
pub enum FiberKind {
    Root(RootFiber),
    Element(ElementFiber),
    Text(TextFiber),
    Function(LuaRegistryKey),
    Context(ContextFiber),
    Fragment(LuaRegistryKey),
}

pub type FiberRef = Rc<RefCell<Fiber>>;
pub type FiberStateNode = Option<usize>;

#[derive(Debug)]
pub struct Fiber {
    pub id: usize,
    pub key: Option<String>,
    pub kind: FiberKind,
    pub child: Option<FiberRef>,
    pub sibling: Option<FiberRef>,
    pub parent: Option<FiberRef>,
    pub alternate: Option<FiberRef>,
    pub flags: Flag,
    pub index: usize,
}

#[derive(Debug)]
pub struct ElementFiber {
    pub memoized_props: Option<LuaRegistryKey>,
    pub pending_props: LuaRegistryKey,
    pub element_tag: String,
    pub state_node: FiberStateNode,
}

#[derive(Debug)]
pub struct TextFiber {
    pub state_node: FiberStateNode,
    pub pending_content: Option<String>,
    pub memoized_content: Option<String>,
}

#[derive(Debug)]
pub struct RootFiber {
    pub state_node: FiberStateNode,
    pub element: LuaRegistryKey,
}

impl PartialEq<String> for TextFiber {
    fn eq(&self, other: &String) -> bool {
        match &self.pending_content {
            Some(content) => content == other,
            None => false,
        }
    }
}

impl PartialEq for TextFiber {
    fn eq(&self, other: &Self) -> bool {
        match (&self.pending_content, &other.memoized_content) {
            (Some(a), Some(b)) => a == b,
            (None, None) => true,
            _ => false,
        }
    }
}

#[derive(Debug)]
pub struct ContextFiber {
    // pub memoized_props: MemoizedContextProps,
    // pub pending_props: PendingContextProps,
}

impl Fiber {
    pub fn new(kind: FiberKind) -> Self {
        Fiber {
            id: util::gen_id(),
            key: None,
            kind,
            child: None,
            sibling: None,
            parent: None,
            alternate: None,
            flags: Flag::NONE,
            index: 0,
        }
    }

    pub fn new_root(lua: &Lua, element: LuaValue) -> Self {
        let props_table = lua.create_table().expect("Failed to create props table");

        props_table
            .set("children", &element)
            .expect("Failed to set children in props table");

        let key = lua
            .create_registry_value(props_table)
            .expect("Failed to create registry key for props");

        let kind = FiberKind::Root(RootFiber {
            state_node: None,
            element: key,
        });

        Fiber::new(kind)
    }
}

impl Fiber {
    pub fn create_work_in_progress(
        lua: &Lua,
        current: &FiberRef,
        element_child: ElementChild,
    ) -> Fiber {
        let mut curr_borrow = current.borrow_mut();

        if let Some(alternate) = &curr_borrow.alternate {
            todo!()
        } else {
            let mut wip = Fiber::from_child(lua, element_child);

            wip.alternate = Some(current.clone());

            wip
        }
    }

    pub fn from_other(lua: &Lua, other_fiber: &FiberRef, element_child: ElementChild) -> Fiber {
        let mut wip = Fiber::create_work_in_progress(lua, other_fiber, element_child);

        wip.sibling = None;
        wip.index = 1;

        wip
    }

    pub fn into_ref(self) -> FiberRef {
        Rc::new(RefCell::new(self))
    }
}

bitflags::bitflags! {
    #[derive(Debug, Clone, Copy, PartialEq, Eq)]
    pub struct Flag: u8 {
        const NONE = 0;
        const PLACEMENT = 1 << 0;
        const UPDATE = 1 << 1;
        const DELETE = 1 << 2;
        const CHILD_DELETE = 1 <<3;
    }
}

impl Fiber {
    pub fn set_flags(&mut self, flags: Flag) {
        self.flags |= flags;
    }

    pub fn clear_flags(&mut self, flags: Flag) {
        self.flags &= !flags;
    }

    pub fn check_flags(&self, flags: Flag) -> bool {
        self.flags.contains(flags)
    }

    pub fn reset_flags(&mut self) {
        self.flags = Flag::NONE;
    }
}

impl From<Element> for Fiber {
    fn from(element: Element) -> Self {
        match element.kind {
            ElementKind::Text(str) => {
                let kind = FiberKind::Text(TextFiber {
                    state_node: None,
                    pending_content: Some(str),
                    memoized_content: None,
                });

                Fiber::new(kind)
            }
            ElementKind::Element(tag, props) => {
                let kind = FiberKind::Element(ElementFiber {
                    element_tag: tag,
                    state_node: None,
                    pending_props: props,
                    memoized_props: None,
                });
                Fiber::new(kind)
            }
            ElementKind::Component(key) => {
                let kind = FiberKind::Function(key);
                Fiber::new(kind)
            }
            ElementKind::Fragment(key) => {
                let kind = FiberKind::Fragment(key);
                Fiber::new(kind)
            }
        }
    }
}

pub enum KindTag {
    Root,
    Element,
    Text,
    Function,
    Context,
    Fragment,
}

impl Fiber {
    pub fn from_child(lua: &Lua, child: ElementChild) -> Self {
        match child {
            ElementChild::Text(str) => {
                let kind = FiberKind::Text(TextFiber {
                    state_node: None,
                    pending_content: Some(str),
                    memoized_content: None,
                });
                Fiber::new(kind)
            }
            ElementChild::Table(key) => {
                let kind = FiberKind::Fragment(key);
                Fiber::new(kind)
            }
            ElementChild::Element(key) => {
                let element = lua
                    .registry_value::<Element>(&key)
                    .expect("Failed to retrieve Element from registry");
                Fiber::from(element)
            }
        }
    }

    pub fn get_kind_tag(&self) -> KindTag {
        match &self.kind {
            FiberKind::Root(_) => KindTag::Root,
            FiberKind::Element(_) => KindTag::Element,
            FiberKind::Text(_) => KindTag::Text,
            FiberKind::Function(_) => KindTag::Function,
            FiberKind::Context(_) => KindTag::Context,
            FiberKind::Fragment(_) => KindTag::Fragment,
        }
    }
}

/// Print the fiber tree structure recursively with indentation
pub fn print_fiber_tree(fiber: &FiberRef, out: &mut String, depth: usize, prefix: &str) {
    let f = fiber.borrow();

    // Decide branch marker
    let has_child_or_sibling = f.child.is_some() || f.sibling.is_some();
    let mark = if has_child_or_sibling {
        "├╴"
    } else {
        "└╴"
    };
    let indent = if depth > 0 {
        format!("{}{}", prefix, mark)
    } else {
        prefix.to_string()
    };

    // Tag text
    let mut entry = String::new();
    match &f.kind {
        FiberKind::Fragment(_) => {
            entry.push_str(&format!(" {:?}", f.kind));
        }
        FiberKind::Root(_) => {
            entry.push_str(" fiber root");
        }
        FiberKind::Text(text) => {
            entry.push_str(&format!(
                "#[{}]",
                text.pending_content.clone().unwrap_or("".to_string())
            ));
        }
        FiberKind::Function(_) => {
            entry.push_str("󰊕 Component");
        }
        FiberKind::Context(_) => {
            entry.push_str("󰨾 context");
        }
        FiberKind::Element(el) => {
            entry.push_str(&format!(" element({:?})", el.element_tag));
            // if let Some(children) = f.memoized_props.children_as_str() {
            //     entry.push(' ');
            //     entry.push_str(&format!("#[{}]", children));
            // }
        }
    }

    if let Some(key) = &f.key {
        entry.push_str(&format!(" [key = {}]", key));
    }

    // Always print ID
    entry.push_str(&format!("  {}", f.id));

    // Add this line to the output
    out.push_str(&format!("{}{}\n", indent, entry));

    drop(f); // release borrow before recursion

    // Traverse child
    if let Some(child) = fiber.borrow().child.clone() {
        let new_prefix = if depth > 0 {
            format!("{}│ ", prefix)
        } else {
            String::new()
        };
        print_fiber_tree(&child, out, depth + 1, &new_prefix);
    }

    // Traverse sibling
    if let Some(sibling) = fiber.borrow().sibling.clone() {
        print_fiber_tree(&sibling, out, depth, prefix);
    }
}

/// Print the complete fiber tree starting from the root
pub fn print_complete_fiber_tree(root: &FiberRef) -> String {
    let mut out = String::new();
    print_fiber_tree(root, &mut out, 0, "");
    out
}
