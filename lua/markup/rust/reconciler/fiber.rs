use crate::prelude::*;
use bitflags::bitflags;
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
pub enum FiberTag {
    Function,
    Fragment,
    Element,
    Text,
    Root,
    Context,
}

pub enum FiberType {
    HostComponent,
    HostText,
    HostRoot,
    FunctionComponent,
    ClassComponent,
    ContextProvider,
    ContextConsumer,
}

pub type FiberRef = Rc<RefCell<Fiber>>;

pub type FiberProps = Rc<LuaProps>;

pub type FiberStateNode = Rc<Node>;

pub struct Fiber {
    pub pending_props: Option<FiberProps>,
    pub memoized_props: Option<FiberProps>,
    pub tag: FiberTag,
    pub return_fiber: Option<FiberRef>,
    pub state_node: Option<FiberStateNode>,
    pub alternate: Option<FiberRef>,
    pub child: Option<FiberRef>,
    pub sibling: Option<FiberRef>,
    pub index: usize,
    pub deletions: Option<Vec<FiberRef>>,
    pub flags: Flag,
}

impl Fiber {
    pub fn new(tag: FiberTag, props: Option<FiberProps>) -> Self {
        Self {
            pending_props: props,
            memoized_props: None,
            tag,
            return_fiber: None,
            state_node: None,
            alternate: None,
            child: None,
            sibling: None,
            index: 0,
            deletions: None,
            flags: Flag::NONE,
        }
    }

    pub fn new_root(lsx: Rc<Lsx>) -> Self {
        let root_fiber = Fiber::new(FiberTag::Root, None);
        root_fiber
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
    pub fn create_work_in_progress(
        current: &FiberRef,
        pending_props: Option<FiberProps>,
    ) -> FiberRef {
        let mut current_borrow = current.borrow_mut();

        if let Some(alternate) = &current_borrow.alternate {
            let mut wip = alternate.borrow_mut();
            wip.pending_props = pending_props.clone();
            drop(wip);

            alternate.clone()
        } else {
            let mut wip = Fiber::new(
                current_borrow.tag.clone(),
                current_borrow.pending_props.clone(),
            );

            wip.state_node = current_borrow.state_node.clone();
            wip.alternate = Some(current.clone());

            let wip_ref = Rc::new(RefCell::new(wip));
            current_borrow.alternate = Some(wip_ref.clone());

            wip_ref
        }
    }
}

fn gen_id() -> String {
    use std::sync::atomic::{AtomicUsize, Ordering};
    static COUNTER: AtomicUsize = AtomicUsize::new(0);
    format!("fiber-{}", COUNTER.fetch_add(1, Ordering::SeqCst))
}
