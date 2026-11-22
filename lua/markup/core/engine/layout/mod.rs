//! Layout pass.
//!
//! [`measure`] handles what every node shares: caching, margin, padding and
//! sizes. A [`Strategy`] only arranges children inside a content box, so a new
//! layout mode is one new file plus one arm in [`strategy`].

pub mod absolute;
mod anonymous;
mod block;
mod flex;
mod grid;
mod inline;
mod text;
mod wrap;

use super::style::{Display, Length, Style};
use super::tree::{Collapse, Index, Memo, Size, Tree};

/// How many sizes a node keeps for constraints other than its last.
const MEMO: usize = 8;

/// What a parent asks of a child. Sizes are of the margin box.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Constraints {
    /// Measure this item's content for its automatic flex minimum.
    pub ignore_own_width: bool,
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
    /// Keep each word whole, even past `width`. A word longer than its line
    /// still breaks when drawn, as with CSS `overflow-wrap: break-word`, but
    /// the narrowest a node can be is its longest word, as CSS `min-content`.
    pub whole_words: bool,
    /// Percentage widths depending on this intrinsic measurement resolve as auto.
    pub shares_as_auto: bool,
}

impl Constraints {
    pub fn available(width: i32) -> Self {
        Constraints {
            ignore_own_width: false,
            width,
            height: None,
            exact_width: None,
            exact_height: None,
            intrinsic: false,
            fit: false,
            whole_words: false,
            shares_as_auto: false,
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

    /// The narrowest a node can be: as narrow as wrapping allows, with each
    /// word whole.
    pub fn min_content() -> Self {
        Constraints {
            whole_words: true,
            ..Self::fit_content(0)
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
    pub whole_words: bool,
    pub shares_as_auto: bool,
}

impl Space {
    /// Whether text may break at `width` in this space.
    pub fn can_wrap(self) -> bool {
        !self.intrinsic || self.fit
    }

    /// Constraints for a child that flows in this space.
    pub fn child(self, width: i32) -> Constraints {
        Constraints {
            height: self.height,
            intrinsic: self.intrinsic,
            fit: self.fit,
            whole_words: self.whole_words,
            shares_as_auto: self.shares_as_auto,
            ..Constraints::available(width)
        }
    }
}

/// Arranges the children of one kind of node.
pub trait Strategy {
    /// Writes each child's offset and returns the size of the content box.
    fn arrange(&self, tree: &mut Tree, node: Index, space: Space) -> Size;
}

fn strategy(tree: &Tree, index: Index) -> &'static dyn Strategy {
    let node = tree.node(index);
    match node.display {
        // An inline given a size is a box, as CSS `inline-block`, and so is a
        // flex or grid item, which CSS makes a block: what it holds lays out
        // as in a block, its text wrapping inside it.
        Display::Inline if is_inline_block(&node.style) || inline::is_item(tree, index) => {
            &block::Block
        }
        Display::Block => &block::Block,
        Display::Inline => &inline::Inline,
        Display::Flex => &flex::Flex,
        Display::Grid => &grid::Grid,
        Display::Text => &text::Text,
        Display::Contents => unreachable!("contents nodes are skipped by flow iteration"),
    }
}

/// Whether an inline is sized, so it lays out as CSS `inline-block` does.
pub(super) fn is_inline_block(style: &Style) -> bool {
    let extra = style.extra();
    style.width != Length::Auto
        || style.height != Length::Auto
        || extra.min_width != Length::Auto
        || extra.max_width != Length::Auto
}

fn limit(value: i32, min: Length, max: Length, available: i32) -> i32 {
    let value = max.resolve(available).map_or(value, |max| value.min(max));
    min.resolve(available).map_or(value, |min| value.max(min))
}

/// The preferred width for this pass through layout.
fn used_width(style: &Style, constraints: Constraints) -> Length {
    let share = matches!(style.width, Length::Full | Length::Fraction(_));
    if constraints.ignore_own_width || (share && constraints.shares_as_auto) {
        Length::Auto
    } else {
        style.width
    }
}

fn content_space(style: &Style, constraints: Constraints) -> Space {
    let used = used_width(style, constraints);
    let edges_x = style.margin.horizontal() + style.inner().horizontal();
    let edges_y = style.margin.vertical() + style.inner().vertical();

    let width = constraints
        .exact_width
        .map(|exact| exact - edges_x)
        .or(used.resolve(constraints.width))
        .unwrap_or(constraints.width - edges_x);
    // Children are laid out in the width the node will end up with, so a
    // `max_width` narrows what they get rather than cutting them off after.
    let extra = style.extra();
    let width = limit(width, extra.min_width, extra.max_width, constraints.width);

    let height = constraints
        .exact_height
        .map(|exact| exact - edges_y)
        .or(style
            .height
            .resolve(constraints.height.unwrap_or(0))
            .filter(|_| constraints.height.is_some() || matches!(style.height, Length::Cells(_))));

    let exact = constraints.exact_width.is_some() || used.resolve(0).is_some();

    Space {
        width: width.max(0),
        height: height.map(|height| height.max(0)),
        intrinsic: (constraints.intrinsic || used == Length::Fit) && !exact,
        fit: constraints.fit
            || (used == Length::Fit && !constraints.intrinsic)
            || style.extra().max_width.resolve(constraints.width).is_some(),
        whole_words: constraints.whole_words,
        shares_as_auto: !exact
            && (constraints.shares_as_auto || constraints.intrinsic || used == Length::Fit),
    }
}

/// Lays out a node and returns its margin box size. A clean node asked the same
/// thing keeps its cached result, so only dirty paths do any work.
///
/// Flex and grid ask an item for its size in several ways before placing it.
/// While `tree.sizing` is set only the size matters, so a clean node answers
/// from the sizes it found since it was last dirty, rather than the one cached
/// layout each way would otherwise throw out for the next. What a sizing
/// pass lays out keeps no cached layout, so the placing pass that follows
/// places it again.
pub fn measure(tree: &mut Tree, index: Index, constraints: Constraints) -> Size {
    let node = tree.node(index);
    if !node.dirty && node.geometry.constraints == Some(constraints) {
        return node.geometry.outer;
    }
    if node.dirty {
        tree.node_mut(index).memo.clear();
    } else if tree.sizing {
        // Sized before in this way: what it leaves for its parent is restored.
        if let Some(&(_, memo)) = node.memo.iter().find(|(c, _)| *c == constraints) {
            let geometry = &mut tree.node_mut(index).geometry;
            geometry.content = memo.content;
            geometry.outer = memo.outer;
            geometry.baseline = memo.baseline;
            geometry.margin_top = memo.margin_top;
            geometry.margin_bottom = memo.margin_bottom;
            geometry.collapses_through = memo.collapses_through;
            // Its own box no longer matches how what it holds was placed.
            geometry.constraints = None;
            return memo.outer;
        }
    }
    let node = tree.node(index);

    let display = node.display;
    let style = &node.style;
    let extra = style.extra();
    let mut space = content_space(style, constraints);

    let edges_x = style.margin.horizontal() + style.inner().horizontal();
    let edges_y = style.margin.vertical() + style.inner().vertical();
    let width = used_width(style, constraints);
    let (min_width, max_width) = (extra.min_width, extra.max_width);
    let (min_height, max_height) = (extra.min_height, extra.max_height);

    // What collapses through this node, if anything, is up to its strategy:
    // only a block lets the margins of its children through.
    let margin = style.margin;

    // A fit-content box chooses its width before laying out its children.
    // Percentages that depend on this width are auto during intrinsic sizing.
    let strategy = strategy(tree, index);
    let fit_box = space.intrinsic
        && space.fit
        && !space.whole_words
        && (display.fills_width() || lays_out_as_block(tree, index));
    if fit_box {
        let sizing = std::mem::replace(&mut tree.sizing, true);
        let preferred = strategy
            .arrange(
                tree,
                index,
                Space {
                    fit: false,
                    shares_as_auto: true,
                    ..space
                },
            )
            .width;
        let mut width = preferred;
        if preferred > space.width {
            let minimum = Constraints {
                height: constraints.height,
                ignore_own_width: constraints.ignore_own_width,
                shares_as_auto: true,
                ..Constraints::min_content()
            };
            let minimum = measure(tree, index, minimum).width - edges_x;
            width = space.width.max(minimum);
        }
        tree.sizing = sizing;
        space.width = limit(width, min_width, max_width, constraints.width);
        space.intrinsic = false;
        space.fit = false;
        space.shares_as_auto = false;
    }
    // Laid out anew: pieces of an earlier wrap would paint it where it no
    // longer is. A run that flows it again sets them after this.
    tree.node_mut(index).fragments = None;
    let geometry = &mut tree.node_mut(index).geometry;
    geometry.margin_top = Collapse::of(margin.top);
    geometry.margin_bottom = Collapse::of(margin.bottom);
    geometry.collapses_through = false;
    geometry.baseline = None;

    #[cfg(test)]
    {
        tree.arranged += 1;
    }
    let mut content = strategy.arrange(tree, index, space);

    let fills = display.fills_width() && width != Length::Fit && !constraints.intrinsic;
    if fit_box || constraints.exact_width.is_some() {
        content.width = space.width;
    } else if width.resolve(constraints.width).is_some() || fills {
        // As CSS: a box with a width, or one that fills it, keeps it. What
        // is wider than it runs past it rather than widening it.
        content.width = space.width;
    }
    content.width = limit(content.width, min_width, max_width, constraints.width);

    // As CSS: a box sized to its content, such as `width = "fit"`, lays out
    // what it holds in the width that was found, so a block in it fills it.
    // Only done when such a block came out narrower, which is all it changes.
    if space.intrinsic
        && lays_out_as_block(tree, index)
        && narrower_block(tree, index, content.width)
    {
        let width = content.width;
        content = strategy.arrange(
            tree,
            index,
            Space {
                width,
                intrinsic: false,
                fit: false,
                ..space
            },
        );
        content.width = width;
    }

    if constraints.exact_height.is_some() {
        content.height = space.height.unwrap_or(content.height);
    } else if let Some(definite) = space.height {
        // As CSS: a box keeps its height, and what is taller runs past it.
        // `min_height` is what grows with the content.
        content.height = definite;
    }
    let available_height = constraints.height.unwrap_or(0);
    content.height = limit(content.height, min_height, max_height, available_height);

    let outer = Size {
        width: content.width + edges_x,
        height: content.height + edges_y,
    };

    let sizing = tree.sizing;
    let node = tree.node_mut(index);
    node.geometry.content = content;
    node.geometry.outer = outer;
    // Only a placing pass leaves what the node holds where its box says.
    node.geometry.constraints = (!sizing).then_some(constraints);
    node.dirty = false;
    let geometry = &node.geometry;
    let memo = Memo {
        content,
        outer,
        baseline: geometry.baseline,
        margin_top: geometry.margin_top,
        margin_bottom: geometry.margin_bottom,
        collapses_through: geometry.collapses_through,
    };
    if node.memo.len() >= MEMO {
        node.memo.remove(0);
    }
    node.memo.push((constraints, memo));
    outer
}

/// Whether a node arranges what it holds as a block does: see [`strategy`].
fn lays_out_as_block(tree: &Tree, index: Index) -> bool {
    let node = tree.node(index);
    match node.display {
        Display::Block => true,
        Display::Inline => is_inline_block(&node.style) || inline::is_item(tree, index),
        _ => false,
    }
}

/// Whether a block in the flow of `index` that fills its width with an `auto`
/// one is narrower than `width`.
fn narrower_block(tree: &mut Tree, index: Index, width: i32) -> bool {
    let mut found = false;
    tree.for_each_flow_child(index, false, &mut |tree, child| {
        let node = tree.node(child);
        let fills = node.display.fills_width() && node.style.width == Length::Auto;
        found = found || (fills && node.geometry.outer.width < width);
    });
    found
}

/// Splits `total` by `weights` in whole cells, as a browser would snap the
/// edges of fractional shares to a grid of cells: each edge goes to the
/// nearest cell, back one at exactly half, as centering does. The shares
/// always add up to `total`.
pub(super) fn share(total: i32, weights: &[f32]) -> Vec<i32> {
    let sum: f64 = weights.iter().map(|&weight| weight as f64).sum();
    if sum <= 0.0 {
        return vec![0; weights.len()];
    }

    let mut shares = Vec::with_capacity(weights.len());
    let (mut weight_so_far, mut edge) = (0.0, 0);
    for &weight in weights {
        weight_so_far += weight as f64;
        let exact = total as f64 * weight_so_far / sum;
        let next = (exact - 0.5).ceil() as i32;
        shares.push(next - edge);
        edge = next;
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
    use super::super::style::{Display, Distribute, Edges, Length, Track, WhiteSpace};
    use super::super::tree::{Index, Size, Tree};
    use super::testing::*;

    /// A card as the stress test has them: a bordered block holding flex rows.
    fn cards(tree: &mut Tree) -> Index {
        let mut items = Vec::new();
        for card in 0..3 {
            let id = 100 + card * 10;
            let (name, value) = (text(tree, id, "card"), text(tree, id + 1, "42%"));
            let left = element(tree, id + 2, Display::Block, &[name]);
            let right = element(tree, id + 3, Display::Block, &[value]);
            let row = element(tree, id + 4, Display::Flex, &[left, right]);
            tree.node_mut(row).style.extra_mut().justify = Distribute::Between;
            let words = text(tree, id + 5, "signal effect memo");
            let line = element(tree, id + 6, Display::Flex, &[words]);
            let item = element(tree, id + 7, Display::Block, &[row, line]);
            tree.node_mut(item).style.padding = Edges {
                top: 1,
                right: 1,
                bottom: 1,
                left: 1,
            };
            items.push(item);
        }
        let grid = element(tree, 1, Display::Grid, &items);
        tree.node_mut(grid).style.extra_mut().columns = vec![Track::Fr(1.0); 3];
        grid
    }

    #[test]
    fn sizing_again_in_a_way_seen_before_lays_nothing_out() {
        let mut tree = Tree::default();
        let root = cards(&mut tree);
        let intrinsic = super::Constraints::intrinsic(60);
        let narrowest = super::Constraints::min_content();
        let size = |tree: &mut Tree, constraints| {
            tree.sizing = true;
            let size = super::measure(tree, root, constraints);
            tree.sizing = false;
            size
        };

        let wide = size(&mut tree, intrinsic);
        let narrow = size(&mut tree, narrowest);
        let arranged = tree.arranged;
        assert_eq!(size(&mut tree, intrinsic), wide);
        assert_eq!(size(&mut tree, narrowest), narrow);
        assert_eq!(tree.arranged, arranged);
    }

    #[test]
    fn a_grid_of_flex_cards_sizes_each_way_once() {
        let mut tree = Tree::default();
        let root = cards(&mut tree);
        measure(&mut tree, root, 60);
        let nodes = tree.len();
        // Each sizing used to throw out the size the one before it found, and
        // nesting multiplied that: these 25 nodes took 409 layouts, 277 now.
        // Deeper trees, such as the stress test's, gain far more.
        assert!(
            tree.arranged <= nodes * 12,
            "{} layouts of {nodes} nodes",
            tree.arranged
        );
    }

    #[test]
    fn placing_after_sizing_leaves_children_where_a_fresh_layout_does() {
        let fresh = {
            let mut tree = Tree::default();
            let root = cards(&mut tree);
            measure(&mut tree, root, 60);
            geometry(&tree)
        };

        let mut tree = Tree::default();
        let root = cards(&mut tree);
        measure(&mut tree, root, 60);
        // Sized other ways, as a parent flex would, then placed again.
        tree.sizing = true;
        super::measure(&mut tree, root, super::Constraints::min_content());
        super::measure(&mut tree, root, super::Constraints::intrinsic(20));
        tree.sizing = false;
        measure(&mut tree, root, 60);
        assert_eq!(geometry(&tree), fresh);

        // A change deep inside is laid out anew, however it was sized before.
        let words = tree.index_of(105).unwrap();
        tree.node_mut(words).text = "a much longer line of words".to_string();
        tree.node_mut(words).text_width = 27;
        tree.mark_dirty(words);
        tree.sizing = true;
        super::measure(&mut tree, root, super::Constraints::intrinsic(60));
        tree.sizing = false;
        measure(&mut tree, root, 60);
        let changed = geometry(&tree);

        let mut other = Tree::default();
        let root = cards(&mut other);
        let words = other.index_of(105).unwrap();
        other.node_mut(words).text = "a much longer line of words".to_string();
        other.node_mut(words).text_width = 27;
        measure(&mut other, root, 60);
        assert_eq!(changed, geometry(&other));
    }

    /// Where every node is, by client id.
    fn geometry(tree: &Tree) -> Vec<(u32, i32, i32, i32, i32)> {
        let mut all: Vec<_> = (100..130)
            .chain([1])
            .filter_map(|id| tree.index_of(id).ok())
            .map(|index| {
                let node = tree.node(index);
                let geometry = node.geometry;
                (
                    node.client,
                    geometry.x,
                    geometry.y,
                    geometry.outer.width,
                    geometry.outer.height,
                )
            })
            .collect();
        all.sort();
        all
    }

    #[test]
    fn clipped_nodes_take_exactly_their_height() {
        let mut tree = Tree::default();
        let (a, b) = (text(&mut tree, 1, "a"), text(&mut tree, 2, "b"));
        let first = element(&mut tree, 3, Display::Block, &[a]);
        let second = element(&mut tree, 4, Display::Block, &[b]);
        let root = element(&mut tree, 5, Display::Block, &[first, second]);
        let style = &mut tree.node_mut(root).style;
        style.height = Length::Cells(1);
        style.extra_mut().clip = true;

        assert_eq!(measure(&mut tree, root, 10).height, 1);
    }

    #[test]
    fn clipped_nodes_do_not_grow_with_their_content() {
        let mut tree = Tree::default();
        let wide = element(&mut tree, 1, Display::Block, &[]);
        tree.node_mut(wide).style.width = Length::Cells(50);
        let clipped = element(&mut tree, 2, Display::Block, &[wide]);
        tree.node_mut(clipped).style.extra_mut().clip = true;
        let root = element(&mut tree, 3, Display::Block, &[clipped]);

        assert_eq!(measure(&mut tree, root, 10).width, 10);
    }

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
        style.margin = Edges {
            left: 2,
            ..Edges::default()
        };
        style.padding = Edges {
            top: 1,
            right: 3,
            bottom: 1,
            left: 0,
        };

        assert_eq!(
            measure(&mut tree, root, 40),
            Size {
                width: 8,
                height: 3
            }
        );
    }

    #[test]
    fn explicit_sizes_grow_the_content_box() {
        let mut tree = Tree::default();
        let label = text(&mut tree, 1, "abc");
        let root = element(&mut tree, 2, Display::Block, &[label]);
        let style = &mut tree.node_mut(root).style;
        style.width = Length::Cells(10);
        style.height = Length::Cells(4);

        assert_eq!(
            measure(&mut tree, root, 40),
            Size {
                width: 10,
                height: 4
            }
        );
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
