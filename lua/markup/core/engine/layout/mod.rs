//! Layout pass.
//!
//! [`measure`] handles what every node shares: caching, margin, padding and
//! explicit sizes. A [`Strategy`] only arranges children inside a content box,
//! so a new layout mode is one new file plus one arm in [`strategy`].

mod block;
mod inline;
mod text;

use super::style::Display;
use super::tree::{Index, Size, Tree};

/// Arranges the children of one kind of node.
pub trait Strategy {
    /// Writes each child's offset and returns the size of the content box.
    fn arrange(&self, tree: &mut Tree, node: Index, available_width: i32) -> Size;
}

fn strategy(display: Display) -> &'static dyn Strategy {
    match display {
        Display::Block => &block::Block,
        Display::Inline => &inline::Inline,
        Display::Text => &text::Text,
        Display::Contents => unreachable!("contents nodes are skipped by flow iteration"),
    }
}

/// Lays out a node and returns its margin box size. A clean node laid out with
/// the same width keeps its cached result, so only dirty paths do any work.
pub fn measure(tree: &mut Tree, index: Index, available_width: i32) -> Size {
    let node = tree.node(index);
    if !node.dirty && node.geometry.available == available_width {
        return node.geometry.outer;
    }

    let display = node.display;
    let style = &node.style;
    let (margin, padding) = (style.margin, style.padding);
    let (width, height) = (style.width, style.height);

    let edges_x = margin.horizontal() + padding.horizontal();
    let edges_y = margin.vertical() + padding.vertical();
    let fixed_width = width.resolve(available_width);
    let inner_width = fixed_width.unwrap_or(available_width - edges_x).max(0);

    let mut content = strategy(display).arrange(tree, index, inner_width);

    content.width = match fixed_width {
        Some(fixed) => content.width.max(fixed),
        None if display.fills_width() && width != super::style::Length::Fit => {
            content.width.max(inner_width)
        }
        None => content.width,
    };
    if let Some(fixed) = height.resolve(0) {
        content.height = content.height.max(fixed);
    }

    let outer = Size {
        width: content.width + edges_x,
        height: content.height + edges_y,
    };

    let node = tree.node_mut(index);
    node.geometry.content = content;
    node.geometry.outer = outer;
    node.geometry.available = available_width;
    node.dirty = false;
    outer
}

/// Moves a child to an offset inside its parent's content box.
pub(super) fn place(tree: &mut Tree, index: Index, x: i32, y: i32) {
    let geometry = &mut tree.node_mut(index).geometry;
    geometry.x = x;
    geometry.y = y;
}

#[cfg(test)]
pub(super) mod testing {
    use super::super::style::Display;
    use super::super::tree::{Index, Tree};

    pub fn text(tree: &mut Tree, id: u32, value: &str) -> Index {
        let index = tree.create(id, Display::Text).unwrap();
        let node = tree.node_mut(index);
        node.text = value.to_string();
        node.text_width = value.len() as i32;
        index
    }

    pub fn element(tree: &mut Tree, id: u32, display: Display, children: &[Index]) -> Index {
        let index = tree.create(id, display).unwrap();
        for &child in children {
            tree.insert(index, child, None).unwrap();
        }
        index
    }
}

#[cfg(test)]
mod tests {
    use super::super::style::{Display, Edges, Length};
    use super::super::tree::{Size, Tree};
    use super::testing::*;
    use super::*;

    #[test]
    fn caches_clean_nodes_for_the_same_width() {
        let mut tree = Tree::default();
        let label = text(&mut tree, 1, "hello");
        let root = element(&mut tree, 2, Display::Block, &[label]);
        measure(&mut tree, root, 20);

        tree.node_mut(label).text_width = 99;
        assert_eq!(measure(&mut tree, root, 20).width, 20);

        tree.mark_dirty(label);
        assert_eq!(measure(&mut tree, root, 20).width, 99);
    }

    #[test]
    fn margin_and_padding_surround_the_content() {
        let mut tree = Tree::default();
        let label = text(&mut tree, 1, "abc");
        let root = element(&mut tree, 2, Display::Inline, &[label]);
        let style = &mut tree.node_mut(root).style;
        style.margin = Edges { left: 2, ..Edges::default() };
        style.padding = Edges { top: 1, right: 3, bottom: 1, left: 0 };

        assert_eq!(measure(&mut tree, root, 40), Size { width: 8, height: 3 });
    }

    #[test]
    fn explicit_sizes_grow_the_content_box() {
        let mut tree = Tree::default();
        let label = text(&mut tree, 1, "abc");
        let root = element(&mut tree, 2, Display::Block, &[label]);
        let style = &mut tree.node_mut(root).style;
        style.width = Length::Cells(10);
        style.height = Length::Cells(4);

        assert_eq!(measure(&mut tree, root, 40), Size { width: 10, height: 4 });
    }

    #[test]
    fn fit_blocks_shrink_to_their_content() {
        let mut tree = Tree::default();
        let label = text(&mut tree, 1, "abc");
        let root = element(&mut tree, 2, Display::Block, &[label]);
        tree.node_mut(root).style.width = Length::Fit;

        assert_eq!(measure(&mut tree, root, 40).width, 3);
    }
}
