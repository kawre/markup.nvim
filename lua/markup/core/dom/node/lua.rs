use crate::prelude::*;
use mlua::prelude::*;
use taffy::prelude::*;

#[derive(Clone)]
pub struct LuaNode {
    dom: DomRef,
    node_id: usize,
}

impl LuaNode {
    pub fn new(dom: DomRef, node_id: usize) -> Self {
        LuaNode { dom, node_id }
    }
}

impl LuaUserData for LuaNode {
    fn add_fields<F: LuaUserDataFields<Self>>(fields: &mut F) {
        // fields.add_meta_field("node_id", |_, this| Ok(this.node_id));
    }

    fn add_methods<M: LuaUserDataMethods<Self>>(methods: &mut M) {
        methods.add_method_mut("remove_child", |_, this, child_ud: LuaAnyUserData| {
            let child: LuaNode = child_ud.borrow::<LuaNode>()?.clone();
            let mut tree = this.dom.borrow_mut();
            tree.remove_child(this.node_id, child.node_id);
            Ok(())
        });

        methods.add_method_mut("append_child", |_, this, child_ud: LuaAnyUserData| {
            let child: LuaNode = child_ud.borrow::<LuaNode>()?.clone();
            let mut tree = this.dom.borrow_mut();
            tree.append_child(this.node_id, child.node_id);
            Ok(())
        });

        methods.add_method("contains", |_, this, child_ud: LuaAnyUserData| {
            let child: LuaNode = child_ud.borrow::<LuaNode>()?.clone();
            let tree = this.dom.borrow();
            Ok(tree.contains_child(this.node_id, child.node_id))
        });

        methods.add_method("has_child_nodes", |_, this, ()| {
            let tree = this.dom.borrow();
            Ok(tree.has_child_nodes(this.node_id))
        });

        methods.add_method_mut(
            "compute_layout",
            |lua, this, (available_width, available_height): (LuaInteger, LuaInteger)| {
                let mut tree = this.dom.borrow_mut();

                tree.compute_layout(
                    this.node_id,
                    Size {
                        width: AvailableSpace::from(available_width as f32),
                        height: AvailableSpace::from(available_height as f32),
                    },
                );

                let mut renderer = LineRenderer::new(available_width as usize);
                let (lines, highlights) = renderer.render(&tree, NodeId::from(this.node_id));

                let result = lua.create_table()?;
                result.set("lines", lines)?;
                result.set("extmarks", highlights)?;

                Ok(result)
            },
        );

        methods.add_method("layout", |_, this, ()| {
            let tree = this.dom.borrow();

            // tree.layout

            Ok(())
        });

        methods.add_meta_method(LuaMetaMethod::ToString, |_, this, ()| {
            let mut out = String::new();

            fn print_rec(node_id: NodeId, dom: &DomRef, indent: usize, out: &mut String) {
                let dom_borrow = dom.borrow();
                out.push_str(&format!(
                    "{}Kind: {:?}\n",
                    " ".repeat(indent),
                    dom_borrow.node_from_id(node_id).kind
                ));

                for child_id in dom_borrow.child_ids(node_id) {
                    print_rec(child_id, dom, indent + 2, out);
                }
            }

            let node_id = NodeId::from(this.node_id);
            let dom = this.dom.clone();
            print_rec(node_id, &dom, 0, &mut out);
            Ok(out)
        });
    }
}
