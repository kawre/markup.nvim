use taffy::{NodeId, PrintTree, TraversePartialTree};

use crate::prelude::*;

pub fn print_tree_to_string(tree: &Dom, root: NodeId) -> String {
    let mut output = String::new();
    output.push_str("TREE\n");
    print_node(tree, root, false, String::new(), &mut output);

    fn print_node(
        tree: &Dom,
        node_id: NodeId,
        has_sibling: bool,
        lines_string: String,
        output: &mut String,
    ) {
        let layout = &tree.get_final_layout(node_id);
        let num_children = tree.child_count(node_id);
        let node = tree.node_from_id(node_id);
        let display = tree.get_debug_label(node_id).to_string();

        let fork_string = if has_sibling { "├╴" } else { "└╴" };

        #[cfg(feature = "content_size")]
        {
            use std::fmt::Write as FmtWrite;
            let _ = writeln!(
                output,
                "{lines}{fork} {display} [x: {x:<4} y: {y:<4} w: {width:<4} h: {height:<4} content_w: {content_width:<4} content_h: {content_height:<4} border: l:{bl} r:{br} t:{bt} b:{bb}, padding: l:{pl} r:{pr} t:{pt} b:{pb}] ({key:?})",
                lines = lines_string,
                fork = fork_string,
                display = display,
                x = layout.location.x,
                y = layout.location.y,
                width = layout.size.width,
                height = layout.size.height,
                content_width = layout.content_size.width,
                content_height = layout.content_size.height,
                bl = layout.border.left,
                br = layout.border.right,
                bt = layout.border.top,
                bb = layout.border.bottom,
                pl = layout.padding.left,
                pr = layout.padding.right,
                pt = layout.padding.top,
                pb = layout.padding.bottom,
                key = node_id,
            );
        }
        #[cfg(not(feature = "content_size"))]
        {
            use std::fmt::Write as FmtWrite;

            let _ = writeln!(
                output,
                "{lines}{fork} {display} [x: {x:<4} y: {y:<4} width: {width:<4} height: {height:<4}] ({key:?})",
                lines = lines_string,
                fork = fork_string,
                display = display,
                x = layout.location.x,
                y = layout.location.y,
                width = layout.size.width,
                height = layout.size.height,
                key = node_id,
            );
        }

        let bar = if has_sibling { "│ " } else { "  " };
        let new_string = lines_string + bar;

        for (index, child) in tree.child_ids(node_id).enumerate() {
            let has_sibling = index < num_children - 1;
            print_node(tree, child, has_sibling, new_string.clone(), output);
        }
    }

    output
}
