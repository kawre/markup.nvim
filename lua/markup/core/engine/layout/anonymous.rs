//! Anonymous boxes, as CSS makes them: neighbouring text in a flex or grid
//! container is one item, a block that holds it.

use super::{Constraints, content_space, measure, place, wrap};
use crate::engine::style::{Display, Style};
use crate::engine::tree::{Index, Size, Tree};
use std::sync::LazyLock;

/// The style of an anonymous box: none of its own.
static ANONYMOUS: LazyLock<Style> = LazyLock::new(Style::default);

/// An item of a flex or grid container.
#[derive(Debug, Clone)]
pub enum Unit {
    Node(Index),
    /// Neighbouring text, laid out together in a block of its own.
    Texts(Vec<Index>),
}

impl Unit {
    pub fn style<'a>(&self, tree: &'a Tree) -> &'a Style {
        match self {
            Unit::Node(index) => &tree.node(*index).style,
            Unit::Texts(_) => &ANONYMOUS,
        }
    }

    pub fn measure(&self, tree: &mut Tree, constraints: Constraints) -> Size {
        match self {
            Unit::Node(index) => measure(tree, *index, constraints),
            Unit::Texts(texts) => measure_texts(tree, texts, constraints),
        }
    }

    /// The size the unit would be, without placing what it holds.
    pub fn size(&self, tree: &mut Tree, constraints: Constraints) -> Size {
        let sizing = std::mem::replace(&mut tree.sizing, true);
        let size = self.measure(tree, constraints);
        tree.sizing = sizing;
        size
    }

    /// Baseline relative to the top of the margin box.
    pub fn baseline(&self, tree: &Tree, height: i32) -> i32 {
        match self {
            Unit::Node(index) => {
                let node = tree.node(*index);
                let margin = node.style.margin;
                node.geometry.baseline.map_or(height - margin.bottom, |b| {
                    margin.top + node.style.inner().top + b
                })
            }
            Unit::Texts(_) => height,
        }
    }

    pub fn place(&self, tree: &mut Tree, x: i32, y: i32) {
        match self {
            Unit::Node(index) => place(tree, *index, x, y),
            // The pieces of the text are placed from the block's origin.
            Unit::Texts(texts) => {
                for &text in texts {
                    place(tree, text, x, y);
                }
            }
        }
    }
}

/// The items of a flex or grid container, in tree order.
pub fn items(tree: &mut Tree, node: Index) -> Vec<Unit> {
    let mut units = Vec::new();
    let mut texts = Vec::new();
    tree.for_each_flow_child(node, false, &mut |tree, child| {
        if tree.node(child).display == Display::Text {
            texts.push(child);
        } else {
            close(tree, &mut texts, &mut units);
            units.push(Unit::Node(child));
        }
    });
    close(tree, &mut texts, &mut units);
    units
}

/// Ends a run of text. As CSS: a run of nothing but white space is not drawn.
fn close(tree: &mut Tree, texts: &mut Vec<Index>, units: &mut Vec<Unit>) {
    if texts.is_empty() {
        return;
    }
    let blank = texts.iter().all(|&text| {
        tree.node(text)
            .text
            .chars()
            .all(|character| matches!(character, ' ' | '\t' | '\n'))
    });
    if blank {
        for &text in texts.iter() {
            let node = tree.node_mut(text);
            node.geometry.x = 0;
            node.geometry.y = 0;
            node.geometry.content = Size::default();
            node.geometry.outer = Size::default();
            node.fragments = Some(Vec::new());
            node.dirty = false;
            node.memo.clear();
        }
        texts.clear();
    } else {
        units.push(Unit::Texts(std::mem::take(texts)));
    }
}

/// Lays text out as a block with no style of its own would.
fn measure_texts(tree: &mut Tree, texts: &[Index], constraints: Constraints) -> Size {
    let mut space = content_space(&ANONYMOUS, constraints);
    for &text in texts {
        measure(tree, text, space.child(space.width));
    }
    // As CSS `fit-content`, and `measure` does for any box: no narrower than
    // its longest word.
    if space.intrinsic && space.fit && !space.whole_words && constraints.exact_width.is_none() {
        let longest = wrap::flow(tree, texts, 0, space, false).0.width;
        space.width = space.width.max(longest);
    }
    let wraps = space.can_wrap() && tree.text_wraps(texts[0]);
    let limit = if wraps { space.width } else { i32::MAX };
    let (flowed, _) = wrap::flow(tree, texts, limit, space, !space.whole_words);

    // A block fills the width it is given, and takes the height it is given.
    let width = if constraints.exact_width.is_some() || !constraints.intrinsic {
        space.width
    } else {
        flowed.width
    };
    let height = constraints
        .exact_height
        .or(space.height)
        .unwrap_or(flowed.height);
    Size { width, height }
}
