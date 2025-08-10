use crate::prelude::*;
use mlua::prelude::*;
use std::cell::RefCell;
use std::future::pending;
use std::rc::Rc;

type RootProps = Rc<LuaRegistryKey>;
type FunctionProps = Rc<LuaRegistryKey>;

#[derive(Debug, PartialEq, Default)]
pub struct Node {}

#[derive(Debug)]
pub enum FiberKind {
    Root(LuaRegistryKey),
    Element(ElementFiber),
    Text(String),
    Function(LuaRegistryKey),
    Context(ContextFiber),
    Fragment(LuaRegistryKey),
}

pub type FiberRef = Rc<RefCell<Fiber>>;
pub type FiberStateNode = Rc<Node>;

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
    pub memoized_props: Option<MemoizedProps>,
    pub pending_props: LuaRegistryKey,
    pub element_tag: String,
    pub state_node: Option<FiberStateNode>,
}

#[derive(Debug)]
pub struct ContextFiber {
    // pub memoized_props: MemoizedContextProps,
    // pub pending_props: PendingContextProps,
}

impl Fiber {
    pub fn new(kind: FiberKind) -> Self {
        Fiber {
            id: 0,
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

        let kind = FiberKind::Root(key);

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
                let kind = FiberKind::Text(str);
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

impl Fiber {
    pub fn from_child(lua: &Lua, child: ElementChild) -> Self {
        match child {
            ElementChild::Text(str) => {
                let kind = FiberKind::Text(str);
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
}

/// Print the fiber tree structure recursively with indentation
pub fn print_fiber_tree(fiber: &FiberRef, indent: usize) {
    let indent_str = "  ".repeat(indent);

    let (fiber_type, fiber_id, fiber_flags, has_children) = {
        let fiber_borrow = fiber.borrow();
        let fiber_type = match &fiber_borrow.kind {
            FiberKind::Root(_) => "Root".to_string(),
            FiberKind::Element(ef) => format!("Element({})", ef.element_tag),
            FiberKind::Text(text) => format!("Text({})", text),
            FiberKind::Function(_) => "Function".to_string(),
            FiberKind::Context(_) => "Context".to_string(),
            FiberKind::Fragment(_) => "Fragment".to_string(),
        };
        (
            fiber_type,
            fiber_borrow.id,
            fiber_borrow.flags,
            fiber_borrow.child.is_some(),
        )
    };

    println!(
        "{}├─ {} [id: {}, flags: {:?}]",
        indent_str, fiber_type, fiber_id, fiber_flags
    );

    // Print children recursively
    if has_children {
        let child = fiber.borrow().child.clone();
        if let Some(child_fiber) = child {
            print_fiber_tree(&child_fiber, indent + 1);

            // Print siblings
            let mut current_sibling = child_fiber.borrow().sibling.clone();
            while let Some(sibling) = current_sibling {
                print_fiber_tree(&sibling, indent + 1);
                current_sibling = sibling.borrow().sibling.clone();
            }
        }
    }
}

/// Print the complete fiber tree starting from the root
pub fn print_complete_fiber_tree(root: &FiberRef) {
    println!("\n=== FIBER TREE STRUCTURE ===");
    print_fiber_tree(root, 0);
    println!("=== END FIBER TREE ===\n");
}
