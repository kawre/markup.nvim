use crate::prelude::*;
use bitflags::bitflags;
use mlua::prelude::*;
use std::cell::RefCell;
use std::rc::Rc;

bitflags! {
    pub struct Flag: u8 {
        const NONE = 0;
        const PLACEMENT = 1 << 0;
        const UPDATE = 1 << 1;
        const DELETE = 1 << 2;
        const CHILD_DELETE = 1 <<3;
    }
}

#[derive(Clone, PartialEq)]
pub enum FiberKind {
    Function(LuaFunction),
    Fragment,
    Element,
    Text,
    Root,
    Context,
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

pub type FiberRef = Rc<RefCell<Fiber>>;
pub type FiberStateNode = Rc<Node>;

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
    pub deletions: Option<Vec<FiberRef>>,
    pub flags: Flag,
    pub key: Option<String>,
}

impl Fiber {
    pub fn new(kind: FiberKind, props: ElementProps) -> Self {
        Self {
            pending_props: props,
            memoized_props: None,
            kind,
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

    pub fn new_root(lsx: Rc<Element>) -> Self {
        let root_fiber = Fiber::new(FiberKind::Root, ElementProps::default());
        root_fiber
    }

    pub fn into_ref(self) -> FiberRef {
        Rc::new(RefCell::new(self))
    }

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

            let wip_ref = Rc::new(RefCell::new(wip));
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
            memoized_props: None,
            kind,
            element_kind: Some(lsx_borrow.kind.clone()),
            return_fiber: None,
            state_node: None,
            alternate: None,
            child: None,
            sibling: None,
            index: 0,
            deletions: None,
            flags: Flag::NONE,
            key: lsx_borrow.key.clone(),
        }
    }
}

impl From<&LuaElement> for Fiber {
    fn from(lua_lsx: &LuaElement) -> Self {
        Fiber::from(&lua_lsx.0.clone())
    }
}

fn gen_id() -> String {
    use std::sync::atomic::{AtomicUsize, Ordering};
    static COUNTER: AtomicUsize = AtomicUsize::new(0);
    format!("fiber-{}", COUNTER.fetch_add(1, Ordering::SeqCst))
}

impl Fiber {
    pub fn print_tree(&self) -> String {
        let mut out = String::new();
        self.print_tree_rec(0, &mut out);
        out
    }

    fn print_tree_rec(&self, depth: usize, out: &mut String) {
        use std::fmt::Write;

        let indent = "  ".repeat(depth);
        let kind = match &self.kind {
            FiberKind::Function(_) => "Function",
            FiberKind::Fragment => "Fragment",
            FiberKind::Element => "Element",
            FiberKind::Root => "Root",
            FiberKind::Text => "Text",
            FiberKind::Context => "Context",
        };

        let _ = writeln!(out, "{}{} (key: {:?}", indent, kind, self.key);

        if let Some(child) = &self.child {
            child.borrow().print_tree_rec(depth + 1, out);
        }

        if let Some(sibling) = &self.sibling {
            sibling.borrow().print_tree_rec(depth, out);
        }
    }
}
