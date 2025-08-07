use crate::{prelude::*, util};
use mlua::prelude::*;
use std::cell::RefCell;
use std::rc::Rc;

#[derive(Debug, Clone, PartialEq, Default)]
pub enum FiberKind {
    Function(LuaFunction),
    Fragment,
    Element,
    #[default]
    Text,
    Root,
    Context,
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

pub type FiberRef = Rc<RefCell<Fiber>>;
pub type FiberStateNode = Rc<Node>;

#[derive(Debug, Clone)]
pub struct Fiber {
    pub pending_props: ElementProps,
    pub memoized_props: Option<ElementProps>,
    pub kind: FiberKind,
    pub element_kind: Option<ElementKind>,
    pub return_fiber: Option<FiberRef>,
    pub state_node: Option<FiberStateNode>,
    pub alternate: Option<FiberRef>,
    pub child: Option<FiberRef>,
    pub sibling: Option<FiberRef>,
    pub index: usize,
    pub id: usize,
    pub deletions: Option<Vec<FiberRef>>,
    pub flags: Flag,
    pub key: Option<String>,
}

impl Default for Fiber {
    fn default() -> Self {
        Self {
            id: util::gen_id(),
            pending_props: ElementProps::default(),
            memoized_props: None,
            kind: FiberKind::default(),
            element_kind: None,
            return_fiber: None,
            state_node: None,
            alternate: None,
            child: None,
            sibling: None,
            index: 0,
            deletions: None,
            flags: Flag::NONE,
            key: None,
        }
    }
}

impl Fiber {
    pub fn new(kind: FiberKind, props: ElementProps) -> Self {
        Self {
            pending_props: props,
            kind,
            ..Default::default()
        }
    }

    pub fn new_root(lsx: Rc<Element>) -> Self {
        let root_fiber = Fiber::new(FiberKind::Root, ElementProps::default());
        root_fiber
    }

    pub fn into_ref(self) -> FiberRef {
        Rc::new(RefCell::new(self))
    }

    // This is used to create an alternate fiber to do work on.
    pub fn create_work_in_progress(current: &FiberRef, pending_props: ElementProps) -> FiberRef {
        let mut current_borrow = current.borrow_mut();

        if let Some(alternate) = &current_borrow.alternate {
            let mut wip = alternate.borrow_mut();
            wip.pending_props = pending_props.clone();
            drop(wip);

            alternate.clone()
        } else {
            let mut wip = Fiber::new(
                current_borrow.kind.clone(),
                current_borrow.pending_props.clone(),
            );

            wip.state_node = current_borrow.state_node.clone();
            wip.alternate = Some(current.clone());

            let wip_ref = wip.into_ref();
            current_borrow.alternate = Some(wip_ref.clone());

            wip_ref
        }
    }

    pub fn use_other(other_fiber: &FiberRef, props: ElementProps) -> FiberRef {
        let clone = Fiber::create_work_in_progress(other_fiber, props);

        {
            let mut clone = clone.borrow_mut();
            clone.sibling = None;
            clone.index = 1;
        }

        clone
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

impl From<&ElementRef> for Fiber {
    fn from(lsx: &ElementRef) -> Self {
        let kind = match lsx.kind.clone() {
            ElementKind::Component(func) => FiberKind::Function(func),
            ElementKind::Fragment(_) => FiberKind::Fragment,
            ElementKind::Element(_) => FiberKind::Element,
            ElementKind::Text => FiberKind::Text,
        };
        let lsx_borrow = lsx.as_ref();

        Fiber {
            pending_props: lsx_borrow.props.clone(),
            kind,
            element_kind: Some(lsx_borrow.kind.clone()),
            key: lsx_borrow.key.clone(),
            ..Default::default()
        }
    }
}

impl From<&LuaElement> for Fiber {
    fn from(lua_lsx: &LuaElement) -> Self {
        Fiber::from(&lua_lsx.0.clone())
    }
}

impl PartialEq<ElementKind> for FiberKind {
    fn eq(&self, other: &ElementKind) -> bool {
        match self {
            FiberKind::Function(_) => matches!(other, ElementKind::Component(_)),
            FiberKind::Fragment => matches!(other, ElementKind::Fragment(_)),
            FiberKind::Element => matches!(other, ElementKind::Element(_)),
            FiberKind::Text => matches!(other, ElementKind::Element(_)),
            FiberKind::Root => matches!(other, ElementKind::Element(_)),
            FiberKind::Context => false, // Context is not directly comparable to LsxKind
        }
    }
}

impl Fiber {
    pub fn print_tree(&self) -> String {
        self.print_tree_with_depth(0, "", true)
    }

    fn print_tree_with_depth(&self, depth: usize, prefix: &str, is_last: bool) -> String {
        let mut result = String::new();

        // Create the tree structure markers
        let mark = if is_last { "└╴" } else { "├╴" };
        let indent = if depth > 0 {
            format!("{}{}", prefix, mark)
        } else {
            String::new()
        };

        result.push_str(&indent);

        // Add the fiber content based on its kind
        match &self.kind {
            FiberKind::Root => {
                result.push_str(" fiber root");
            }
            FiberKind::Element => {
                result.push_str(&format!(" {:?}", &self.kind,));

                // Add text content if it's a text element
                if let ElementChildren::Text(text) = &self.pending_props.children {
                    result.push_str(&format!(" #[{}]", text));
                }
            }
            FiberKind::Text => {
                if let ElementChildren::Text(text) = &self.pending_props.children {
                    result.push_str(&format!(" #[{}]", text));
                } else {
                    result.push_str(" text");
                }
            }
            FiberKind::Function(func_name) => {
                result.push_str(&format!(" 󰊕 Component({})", "any"));
            }
            FiberKind::Context => {
                result.push_str(" 󰨾 context");
            }
            FiberKind::Fragment => {
                result.push_str(" fragment");
            }
        }

        // Add key if present
        if let Some(key) = &self.key {
            result.push_str(&format!(" [key = {}]", key));
        }

        // Add fiber kind tag
        result.push_str(&format!(
            " ({})",
            match self.kind {
                FiberKind::Root => "ROOT",
                FiberKind::Element => "ELEMENT",
                FiberKind::Text => "TEXT",
                FiberKind::Function(_) => "FUNCTION",
                FiberKind::Context => "CONTEXT",
                FiberKind::Fragment => "FRAGMENT",
            }
        ));

        // Add fiber ID
        result.push_str(&format!("  {} ", &self.id));

        result.push('\n');

        // Print children
        if let Some(child) = &self.child {
            let child_borrow = child.borrow();
            let has_sibling = child_borrow.sibling.is_some();
            drop(child_borrow);

            let new_prefix = if depth > 0 {
                format!("{}│ ", prefix)
            } else {
                String::new()
            };

            result.push_str(&child.borrow().print_tree_with_depth(
                depth + 1,
                &new_prefix,
                !has_sibling,
            ));

            // Print siblings
            let mut current_sibling = child.borrow().sibling.clone();
            while let Some(sibling) = current_sibling {
                let sibling_borrow = sibling.borrow();
                let has_next_sibling = sibling_borrow.sibling.is_some();
                let next_sibling = sibling_borrow.sibling.clone();
                drop(sibling_borrow);

                result.push_str(&sibling.borrow().print_tree_with_depth(
                    depth + 1,
                    &new_prefix,
                    !has_next_sibling,
                ));

                current_sibling = next_sibling;
            }
        }

        result
    }
}
