use super::{Space, Strategy, measure, place};
use crate::engine::tree::{Index, Size, Tree};

/// Lays children out left to right on one line.
pub struct Inline;

impl Strategy for Inline {
    fn arrange(&self, tree: &mut Tree, node: Index, space: Space) -> Size {
        let entry = tree.node_mut(node);
        entry.fragments = None;
        let (reverse, spacing) = (entry.style.reverse, entry.style.spacing);
        let mut size = Size::default();
        let mut first = true;

        tree.for_each_flow_child(node, reverse, &mut |tree, child| {
            if !first {
                size.width += spacing;
            }
            first = false;

            let outer = measure(tree, child, space.child((space.width - size.width).max(0)));
            place(tree, child, size.width, 0);
            size.width += outer.width;
            size.height = size.height.max(outer.height);
        });

        size
    }
}

#[cfg(test)]
mod tests {
    use super::super::testing::*;
    use crate::engine::style::Display;
    use crate::engine::tree::{Size, Tree};

    #[test]
    fn places_children_side_by_side() {
        let mut tree = Tree::default();
        let a = text(&mut tree, 1, "ab");
        let b = text(&mut tree, 2, "cde");
        let root = element(&mut tree, 3, Display::Inline, &[a, b]);

        assert_eq!(measure(&mut tree, root, 40), Size { width: 5, height: 1 });
        assert_eq!(tree.node(b).geometry.x, 2);
    }

    #[test]
    fn spacing_separates_children() {
        let mut tree = Tree::default();
        let a = text(&mut tree, 1, "ab");
        let b = text(&mut tree, 2, "c");
        let root = element(&mut tree, 3, Display::Inline, &[a, b]);
        tree.node_mut(root).style.spacing = 2;

        assert_eq!(measure(&mut tree, root, 40).width, 5);
        assert_eq!(tree.node(b).geometry.x, 4);
    }

    #[test]
    fn reverse_flips_the_order() {
        let mut tree = Tree::default();
        let a = text(&mut tree, 1, "ab");
        let b = text(&mut tree, 2, "cde");
        let root = element(&mut tree, 3, Display::Inline, &[a, b]);
        tree.node_mut(root).style.reverse = true;

        measure(&mut tree, root, 40);

        assert_eq!(tree.node(b).geometry.x, 0);
        assert_eq!(tree.node(a).geometry.x, 3);
    }
}
