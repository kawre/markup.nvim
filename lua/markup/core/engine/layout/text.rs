use super::{Space, Strategy};
use crate::engine::tree::{Index, Size, Tree};

pub struct Text;

impl Strategy for Text {
    fn arrange(&self, tree: &mut Tree, node: Index, _space: Space) -> Size {
        let entry = tree.node_mut(node);
        entry.fragments = None;

        // More than one line tells the parent this text needs line breaking.
        let newlines = entry.text.bytes().filter(|&byte| byte == b'\n').count() as i32;
        Size {
            width: entry.text_width,
            height: 1 + newlines,
        }
    }
}
