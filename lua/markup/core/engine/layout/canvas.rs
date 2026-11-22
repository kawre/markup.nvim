use super::{Space, Strategy};
use crate::engine::tree::{Index, Size, Tree};

pub struct Canvas;

impl Strategy for Canvas {
    fn arrange(&self, tree: &mut Tree, node: Index, _space: Space) -> Size {
        let entry = tree.node(node);
        match entry.canvas.as_deref() {
            Some(canvas) => Size {
                width: canvas.width,
                height: canvas.height,
            },
            None => Size::default(),
        }
    }
}
