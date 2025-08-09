use std::{cell::RefCell, rc::Rc};

use crate::prelude::*;
use mlua::prelude::*;

#[derive(Debug, Clone)]
pub struct Buffer {
    pub id: usize,
    pub lines: Vec<String>,
    pub highlights: Vec<HighlightRange>,
    pub fiber_root: Option<FiberRef>,
    pub element: Option<LuaTable>,
}

impl Buffer {
    pub fn new(id: usize) -> Self {
        // let fiber_root = Fiber::new_root(element);
        Buffer {
            id,
            lines: Vec::new(),
            highlights: Vec::new(),
            fiber_root: None, // fiber_root: fiber_root.into_ref(),
            element: None,
        }
    }

    pub fn attach(&mut self, elemenet: &LuaTable) {
        self.element = Some(elemenet.clone());
    }

    // pub fn render(&mut self) {
    //     let fiber_root = Fiber::new_root(FiberKind::Element, )
    // }
    //
    pub fn reconcile(&mut self) {
        if let Some(fiber_root) = &self.fiber_root {
            reconcile(fiber_root.clone());
            // fiber_root.borrow().print_tree()
        }
    }

    pub fn add_line(&mut self, line: String) {
        self.lines.push(line);
    }

    pub fn clear(&mut self) {
        self.lines.clear();
        self.highlights.clear();
    }
}

pub struct LuaBuffer(pub Rc<RefCell<Buffer>>);

impl LuaUserData for LuaBuffer {
    fn add_methods<M: LuaUserDataMethods<Self>>(methods: &mut M) {
        methods.add_method_mut("attach", |_, this, element: LuaTable| {
            this.0.borrow_mut().attach(&element);
            println!("[markup_core] attach called with element: {:?}", element);
            Ok(())
        });

        methods.add_method_mut("reconcile", |_, this, ()| {
            this.0.borrow_mut().reconcile();
            Ok(this
                .0
                .borrow()
                .fiber_root
                .clone()
                .unwrap()
                .borrow()
                .alternate
                .clone()
                .unwrap()
                .borrow()
                .print_tree())
        });
    }
}
