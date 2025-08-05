pub mod node;
mod props;
use mlua::prelude::*;
pub use node::*;
pub use props::LuaProps;
use std::{cell::RefCell, rc::Rc};
use taffy::{AvailableSpace, Size};

use crate::tree::Tree;

#[derive(Clone)]
pub struct LuaNode {
    tree: Rc<RefCell<Tree>>,
    node_id: usize,
}

impl LuaNode {
    pub fn new(tree: Rc<RefCell<Tree>>, node_id: usize) -> Self {
        LuaNode { tree, node_id }
    }
}

impl LuaUserData for LuaNode {
    fn add_fields<F: LuaUserDataFields<Self>>(fields: &mut F) {
        // fields.add_meta_field("node_id", |_, this| Ok(this.node_id));
    }

    fn add_methods<M: LuaUserDataMethods<Self>>(methods: &mut M) {
        methods.add_method_mut("remove_child", |_, this, child_ud: LuaAnyUserData| {
            let child: LuaNode = child_ud.borrow::<LuaNode>()?.clone();
            let mut tree = this.tree.borrow_mut();
            tree.remove_child(this.node_id, child.node_id);
            Ok(())
        });

        methods.add_method_mut("append_child", |_, this, child_ud: LuaAnyUserData| {
            let child: LuaNode = child_ud.borrow::<LuaNode>()?.clone();
            let mut tree = this.tree.borrow_mut();
            tree.append_child(this.node_id, child.node_id);
            Ok(())
        });

        methods.add_method("contains", |_, this, child_ud: LuaAnyUserData| {
            let child: LuaNode = child_ud.borrow::<LuaNode>()?.clone();
            let tree = this.tree.borrow();
            Ok(tree.contains_child(this.node_id, child.node_id))
        });

        methods.add_method("has_child_nodes", |_, this, ()| {
            let tree = this.tree.borrow();
            Ok(tree.has_child_nodes(this.node_id))
        });

        methods.add_method_mut(
            "compute_layout",
            |_, this, (available_width, available_height): (LuaInteger, LuaInteger)| {
                let mut tree = this.tree.borrow_mut();

                tree.compute_layout(
                    this.node_id,
                    Size {
                        width: AvailableSpace::from(available_width as f32),
                        height: AvailableSpace::from(available_height as f32),
                    },
                    true,
                );

                Ok(())
            },
        );

        methods.add_method("layout", |_, this, ()| {
            let tree = this.tree.borrow();

            // tree.layout

            Ok(())
        });

        methods.add_meta_method(LuaMetaMethod::ToString, |_, this, ()| {
            let tree = this.tree.borrow();
            Ok(tree.to_string(this.node_id))
        });
    }
}
