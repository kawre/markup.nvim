//! Places nodes taken out of flow, once everything in flow has its size.

use super::{Constraints, measure, place};
use crate::engine::style::Length;
use crate::engine::tree::{Index, Tree};

fn depth(tree: &Tree, index: Index) -> usize {
    let mut depth = 0;
    let mut parent = tree.node(index).parent;
    while let Some(index) = parent {
        depth += 1;
        parent = tree.node(index).parent;
    }
    depth
}

/// Outer boxes come first, because inner ones may be placed against them.
pub fn layout(tree: &mut Tree) {
    let mut nodes: Vec<Index> = tree.absolutes().iter().copied().collect();
    if nodes.is_empty() {
        return;
    }
    nodes.sort_by_key(|&index| depth(tree, index));

    for index in nodes {
        if tree.node(index).parent.is_some() {
            position(tree, index);
        }
    }
}

fn position(tree: &mut Tree, index: Index) {
    let block = tree.node(tree.containing_block(index));
    let padding = block.style.padding;
    let width = block.geometry.content.width + padding.horizontal();
    let height = block.geometry.content.height + padding.vertical();

    let style = &tree.node(index).style;
    let inset = style.extra().inset;
    let auto_width = style.width == Length::Auto;
    let auto_height = style.height == Length::Auto;

    // Opposite offsets pin both edges, which decides the size.
    let exact_width = match (inset.left, inset.right) {
        (Some(left), Some(right)) if auto_width => Some((width - left - right).max(0)),
        _ => None,
    };
    let exact_height = match (inset.top, inset.bottom) {
        (Some(top), Some(bottom)) if auto_height => Some((height - top - bottom).max(0)),
        _ => None,
    };

    let outer = measure(
        tree,
        index,
        Constraints {
            width,
            height: Some(height),
            exact_width,
            exact_height,
            intrinsic: exact_width.is_none(),
        },
    );

    let x = inset.left.or(inset.right.map(|right| width - right - outer.width));
    let y = inset.top.or(inset.bottom.map(|bottom| height - bottom - outer.height));
    place(tree, index, x.unwrap_or(0), y.unwrap_or(0));
}
