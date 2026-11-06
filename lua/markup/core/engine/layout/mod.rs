//! Layout pass.
//!
//! [`measure`] handles what every node shares: caching, margin, padding and
//! sizes. A [`Strategy`] only arranges children inside a content box, so a new
//! layout mode is one new file plus one arm in [`strategy`].

pub mod absolute;
mod block;
mod flex;
mod grid;
mod inline;
mod text;
mod wrap;

use super::style::{Display, Length, Style};
use super::tree::{Index, Size, Tree};

/// What a parent asks of a child. Sizes are of the margin box.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Constraints {
    /// Width to fill or fit into.
    pub width: i32,
    /// Height, when the parent has a definite one.
    pub height: Option<i32>,
    /// Sizes the child must take, such as a stretched flex item.
    pub exact_width: Option<i32>,
    pub exact_height: Option<i32>,
    /// Ask for the natural size, so blocks do not fill the width.
    pub intrinsic: bool,
    /// With `intrinsic`, still wrap at `width`, like CSS `fit-content`.
    pub fit: bool,
}

impl Constraints {
    pub fn available(width: i32) -> Self {
        Constraints {
            width,
            height: None,
            exact_width: None,
            exact_height: None,
            intrinsic: false,
            fit: false,
        }
    }

    pub fn intrinsic(width: i32) -> Self {
        Constraints {
            intrinsic: true,
            ..Self::available(width)
        }
    }

    pub fn fit_content(width: i32) -> Self {
        Constraints {
            fit: true,
            ..Self::intrinsic(width)
        }
    }
}

/// The content box a strategy arranges children in.
#[derive(Debug, Clone, Copy)]
pub struct Space {
    pub width: i32,
    pub height: Option<i32>,
    pub intrinsic: bool,
    pub fit: bool,
}

impl Space {
    /// Whether text may break at `width` in this space.
    pub fn can_wrap(self) -> bool {
        !self.intrinsic || self.fit
    }

    /// Constraints for a child that flows in this space.
    pub fn child(self, width: i32) -> Constraints {
        Constraints {
            intrinsic: self.intrinsic,
            fit: self.fit,
            ..Constraints::available(width)
        }
    }
}

/// Arranges the children of one kind of node.
pub trait Strategy {
    /// Writes each child's offset and returns the size of the content box.
    fn arrange(&self, tree: &mut Tree, node: Index, space: Space) -> Size;
}

fn strategy(display: Display) -> &'static dyn Strategy {
    match display {
        Display::Block => &block::Block,
        Display::Inline => &inline::Inline,
        Display::Flex => &flex::Flex,
        Display::Grid => &grid::Grid,
        Display::Text => &text::Text,
        Display::Contents => unreachable!("contents nodes are skipped by flow iteration"),
    }
}

fn limit(value: i32, min: Length, max: Length, available: i32) -> i32 {
    let value = max.resolve(available).map_or(value, |max| value.min(max));
    min.resolve(available).map_or(value, |min| value.max(min))
}

/// Space a node's own style leaves for its content.
fn content_space(style: &Style, constraints: Constraints) -> Space {
    let edges_x = style.margin.horizontal() + style.padding.horizontal();
    let edges_y = style.margin.vertical() + style.padding.vertical();

    let width = constraints
        .exact_width
        .map(|exact| exact - edges_x)
        .or(style.width.resolve(constraints.width))
        .unwrap_or(constraints.width - edges_x);

    let height = constraints
        .exact_height
        .map(|exact| exact - edges_y)
        .or(style.height.resolve(constraints.height.unwrap_or(0)).filter(|_| {
            constraints.height.is_some() || matches!(style.height, Length::Cells(_))
        }));

    let exact = constraints.exact_width.is_some() || style.width.resolve(0).is_some();

    Space {
        width: width.max(0),
        height: height.map(|height| height.max(0)),
        intrinsic: (constraints.intrinsic || style.width == Length::Fit) && !exact,
        fit: constraints.fit || style.width == Length::Fit,
    }
}

/// Lays out a node and returns its margin box size. A clean node asked the same
/// thing keeps its cached result, so only dirty paths do any work.
pub fn measure(tree: &mut Tree, index: Index, constraints: Constraints) -> Size {
    let node = tree.node(index);
    if !node.dirty && node.geometry.constraints == Some(constraints) {
        return node.geometry.outer;
    }

    let display = node.display;
    let style = &node.style;
    let extra = style.extra();
    let space = content_space(style, constraints);

    let edges_x = style.margin.horizontal() + style.padding.horizontal();
    let edges_y = style.margin.vertical() + style.padding.vertical();
    let width = style.width;
    let (min_width, max_width) = (extra.min_width, extra.max_width);
    let (min_height, max_height) = (extra.min_height, extra.max_height);

    let mut content = strategy(display).arrange(tree, index, space);

    let fills = display.fills_width() && width != Length::Fit && !constraints.intrinsic;
    if constraints.exact_width.is_some() {
        content.width = space.width;
    } else if width.resolve(constraints.width).is_some() || fills {
        content.width = content.width.max(space.width);
    }
    content.width = limit(content.width, min_width, max_width, constraints.width);

    if constraints.exact_height.is_some() {
        content.height = space.height.unwrap_or(content.height);
    } else if let Some(definite) = space.height {
        content.height = content.height.max(definite);
    }
    let available_height = constraints.height.unwrap_or(0);
    content.height = limit(content.height, min_height, max_height, available_height);

    let outer = Size {
        width: content.width + edges_x,
        height: content.height + edges_y,
    };

    let node = tree.node_mut(index);
    node.geometry.content = content;
    node.geometry.outer = outer;
    node.geometry.constraints = Some(constraints);
    node.dirty = false;
    outer
}

/// Splits `total` by `weights` in whole cells. The cells lost to rounding go to
/// the largest remainders, so the shares always add up to `total`.
pub(super) fn share(total: i32, weights: &[f32]) -> Vec<i32> {
    let sum: f32 = weights.iter().sum();
    if sum <= 0.0 {
        return vec![0; weights.len()];
    }

    let exact: Vec<f64> = weights
        .iter()
        .map(|&weight| total as f64 * weight as f64 / sum as f64)
        .collect();
    let mut shares: Vec<i32> = exact.iter().map(|share| share.trunc() as i32).collect();

    let mut order: Vec<usize> = (0..weights.len()).filter(|&i| weights[i] > 0.0).collect();
    order.sort_by(|&a, &b| {
        let remainder = |i: usize| (exact[i] - shares[i] as f64).abs();
        remainder(b).total_cmp(&remainder(a))
    });

    let step = total.signum();
    let left = total - shares.iter().sum::<i32>();
    for &position in order.iter().cycle().take(left.unsigned_abs() as usize) {
        shares[position] += step;
    }
    shares
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
    use super::super::tree::{Index, Size, Tree};
    use super::Constraints;

    pub fn measure(tree: &mut Tree, index: Index, width: i32) -> Size {
        super::measure(tree, index, Constraints::available(width))
    }

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
    use super::super::style::{Display, Edges, Length, WhiteSpace};
    use super::super::tree::{Size, Tree};
    use super::testing::*;

    #[test]
    fn share_always_adds_up() {
        for total in [-17, -1, 0, 1, 7, 100] {
            let shares = super::share(total, &[1.0, 2.0, 0.0, 3.5]);
            assert_eq!(shares.iter().sum::<i32>(), total);
            assert_eq!(shares[2], 0);
        }
    }

    #[test]
    fn caches_clean_nodes_for_the_same_width() {
        let mut tree = Tree::default();
        let label = text(&mut tree, 1, "hello");
        let root = element(&mut tree, 2, Display::Block, &[label]);
        let style = &mut tree.node_mut(root).style;
        style.width = Length::Fit;
        style.extra_mut().white_space = Some(WhiteSpace::Nowrap);
        measure(&mut tree, root, 20);

        tree.node_mut(label).text_width = 99;
        assert_eq!(measure(&mut tree, root, 20).width, 5);

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
