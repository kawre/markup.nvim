use super::Strategy;
use crate::engine::tree::{Index, Size, Tree};

pub struct Text;

impl Strategy for Text {
    fn arrange(&self, tree: &mut Tree, node: Index, _available_width: i32) -> Size {
        Size {
            width: tree.node(node).text_width,
            height: 1,
        }
    }
}
