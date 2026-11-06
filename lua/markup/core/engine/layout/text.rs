use super::{Space, Strategy};
use crate::engine::tree::{Index, Size, Tree};

pub struct Text;

impl Strategy for Text {
    fn arrange(&self, tree: &mut Tree, node: Index, _space: Space) -> Size {
        Size {
            width: tree.node(node).text_width,
            height: 1,
        }
    }
}
