//! Flexbox, with integer cells instead of fractional pixels.

use super::{Constraints, Space, Strategy, measure, place, share};
use crate::engine::style::{Align, Direction, Distribute, Length};
use crate::engine::tree::{Index, Size, Tree};
use std::ops::Range;

pub struct Flex;

struct Item {
    index: Index,
    base: i32,
    min: i32,
    max: i32,
    grow: f32,
    shrink: f32,
    main: i32,
    cross: i32,
    align: Align,
    /// Whether the item may take its line's cross size.
    stretches: bool,
}

struct Line {
    items: Range<usize>,
    cross: i32,
}

/// Axis dependent reads, so the algorithm itself only speaks main and cross.
#[derive(Clone, Copy)]
struct Axis {
    column: bool,
}

impl Axis {
    fn main(self, size: Size) -> i32 {
        if self.column { size.height } else { size.width }
    }

    fn cross(self, size: Size) -> i32 {
        if self.column { size.width } else { size.height }
    }

    fn size(self, main: i32, cross: i32) -> Size {
        if self.column {
            Size {
                width: cross,
                height: main,
            }
        } else {
            Size {
                width: main,
                height: cross,
            }
        }
    }

    /// Asks for an item's natural size.
    fn natural(self, space: Space) -> Constraints {
        if self.column {
            // Height depends on wrapping, which depends on the width here.
            Constraints {
                height: space.height,
                ..Constraints::fit_content(space.width)
            }
        } else {
            Constraints::intrinsic(space.width)
        }
    }

    /// Lays an item out at its final main size, and cross size when given.
    fn exact(self, space: Space, main: i32, cross: Option<i32>) -> Constraints {
        if self.column {
            Constraints {
                width: space.width,
                height: Some(main),
                exact_width: cross,
                exact_height: Some(main),
                intrinsic: cross.is_none(),
                fit: cross.is_none(),
            }
        } else {
            Constraints {
                width: main,
                height: cross.or(space.height),
                exact_width: Some(main),
                exact_height: cross,
                intrinsic: false,
                fit: false,
            }
        }
    }
}

fn collect_items(
    tree: &mut Tree,
    node: Index,
    space: Space,
    axis: Axis,
    align: Align,
) -> Vec<Item> {
    let mut ordered = Vec::new();
    tree.for_each_flow_child(node, false, &mut |tree, child| {
        ordered.push((tree.node(child).style.extra().order, child));
    });
    ordered.sort_by_key(|&(order, _)| order);

    let reference = if axis.column {
        space.height.unwrap_or(0)
    } else {
        space.width
    };

    ordered
        .into_iter()
        .map(|(_, index)| {
            let natural = measure(tree, index, axis.natural(space));

            let style = &tree.node(index).style;
            let extra = style.extra();
            let edges = if axis.column {
                style.margin.vertical() + style.inner().vertical()
            } else {
                style.margin.horizontal() + style.inner().horizontal()
            };

            let (min, max) = if axis.column {
                (extra.min_height, extra.max_height)
            } else {
                (extra.min_width, extra.max_width)
            };
            // Like CSS `min-height: auto`: text cannot reflow vertically, so
            // shrinking a column item below its content would just delete rows.
            let automatic = if axis.column { axis.main(natural) } else { 0 };
            let min = min.resolve(reference).map_or(automatic, |min| min + edges);
            let max = max.resolve(reference).map_or(i32::MAX, |max| max + edges);

            let base = match extra.basis {
                Length::Auto => axis.main(natural),
                basis => basis.resolve(reference).unwrap_or(axis.main(natural)),
            };

            let cross_length = if axis.column {
                style.width
            } else {
                style.height
            };
            let item_align = extra.align_self.unwrap_or(align);

            Item {
                index,
                base,
                min,
                max,
                grow: extra.grow,
                shrink: extra.shrink,
                main: base.clamp(min, max.max(min)),
                cross: 0,
                align: item_align,
                stretches: item_align == Align::Stretch && cross_length == Length::Auto,
            }
        })
        .collect()
}

fn break_lines(items: &[Item], limit: Option<i32>, gap: i32) -> Vec<Line> {
    let mut lines = Vec::new();
    let mut start = 0;
    let mut used = 0;

    for (position, item) in items.iter().enumerate() {
        let needed = item.main + if position > start { gap } else { 0 };
        if limit.is_some_and(|limit| position > start && used + needed > limit) {
            lines.push(Line {
                items: start..position,
                cross: 0,
            });
            start = position;
            used = item.main;
        } else {
            used += needed;
        }
    }

    if start < items.len() {
        lines.push(Line {
            items: start..items.len(),
            cross: 0,
        });
    }
    lines
}

/// Grows or shrinks a line to fill `available`. An item that hits a limit is
/// frozen at it, and the rest is shared again among the others.
fn resolve_flexible(items: &mut [Item], available: i32) {
    let natural: i32 = items.iter().map(|item| item.base).sum();
    let growing = natural < available;
    let mut frozen = vec![false; items.len()];

    loop {
        let weights: Vec<f32> = items
            .iter()
            .enumerate()
            .map(|(position, item)| {
                if frozen[position] {
                    0.0
                } else if growing {
                    item.grow
                } else {
                    item.shrink * item.base as f32
                }
            })
            .collect();

        if weights.iter().sum::<f32>() <= 0.0 {
            return;
        }

        let taken: i32 = items
            .iter()
            .enumerate()
            .map(|(position, item)| {
                if frozen[position] {
                    item.main
                } else {
                    item.base
                }
            })
            .sum();

        let shares = share(available - taken, &weights);

        let mut clamped = false;
        for (position, item) in items.iter_mut().enumerate() {
            if frozen[position] {
                continue;
            }
            let target = item.base + shares[position];
            let limited = target.clamp(item.min, item.max.max(item.min));
            item.main = limited;
            if limited != target {
                frozen[position] = true;
                clamped = true;
            }
        }

        if !clamped {
            return;
        }
    }
}

/// Space before each of `count` items, given `free` spare cells.
pub(super) fn offsets(free: i32, count: usize, mode: Distribute) -> Vec<i32> {
    let mut result = vec![0; count];
    if count == 0 || free <= 0 {
        return result;
    }

    let n = count as f64;
    let free_f = free as f64;
    let start = |position: usize| -> i32 {
        let i = position as f64;
        let value = match mode {
            Distribute::Start | Distribute::Stretch => 0.0,
            Distribute::End => free_f,
            Distribute::Center => (free_f / 2.0).floor(),
            Distribute::Between if count == 1 => 0.0,
            Distribute::Between => free_f * i / (n - 1.0),
            Distribute::Around => free_f * (2.0 * i + 1.0) / (2.0 * n),
            Distribute::Evenly => free_f * (i + 1.0) / (n + 1.0),
        };
        value.floor() as i32
    };

    let mut previous = 0;
    for (position, slot) in result.iter_mut().enumerate() {
        let current = start(position);
        *slot = current - previous;
        previous = current;
    }
    result
}

impl Strategy for Flex {
    fn arrange(&self, tree: &mut Tree, node: Index, space: Space) -> Size {
        let style = &tree.node(node).style;
        let extra = style.extra();
        let axis = Axis {
            column: extra.direction == Direction::Column,
        };
        let reverse = style.reverse;
        let wrap = extra.wrap;
        let (justify, align, align_content) = (extra.justify, extra.align, extra.align_content);

        let (row_gap, column_gap) = (
            extra.row_gap.max(style.spacing),
            extra.column_gap.max(style.spacing),
        );
        let (main_gap, cross_gap) = if axis.column {
            (row_gap, column_gap)
        } else {
            (column_gap, row_gap)
        };

        let definite_main = if axis.column {
            space.height
        } else {
            (!space.intrinsic).then_some(space.width)
        };
        let definite_cross = if axis.column {
            (!space.intrinsic).then_some(space.width)
        } else {
            space.height
        };

        // `fit` keeps a row at its natural size, unless that does not fit.
        let fit_limit = (!axis.column && space.intrinsic && space.fit).then_some(space.width);

        let mut items = collect_items(tree, node, space, axis, align);
        let limit = definite_main.or(fit_limit).filter(|_| wrap);
        let mut lines = break_lines(&items, limit, main_gap);

        // Main sizes, line by line.
        for line in &lines {
            let line_items = &mut items[line.items.clone()];
            let gaps = main_gap * (line_items.len() as i32 - 1);

            if let Some(main) = definite_main {
                resolve_flexible(line_items, main - gaps);
            } else if let Some(limit) = fit_limit {
                let natural: i32 = line_items.iter().map(|item| item.base).sum();
                if natural + gaps > limit {
                    resolve_flexible(line_items, limit - gaps);
                }
            }
        }

        // Cross sizes follow from the main size each item ended up with.
        for line in &mut lines {
            for item in &mut items[line.items.clone()] {
                let outer = measure(tree, item.index, axis.exact(space, item.main, None));
                item.cross = axis.cross(outer);
                line.cross = line.cross.max(item.cross);
            }
        }

        let count = lines.len() as i32;
        let cross_gaps = cross_gap * (count - 1).max(0);
        let natural_cross: i32 = lines.iter().map(|line| line.cross).sum::<i32>() + cross_gaps;

        // A single line takes the whole container, several share what is left.
        let mut line_offsets = vec![0; lines.len()];
        if let Some(cross) = definite_cross {
            let free = cross - natural_cross;
            if lines.len() == 1 && !wrap {
                lines[0].cross = cross;
            } else if free > 0 {
                if align_content == Distribute::Stretch {
                    let shares = share(free, &vec![1.0; lines.len()]);
                    for (line, extra_cross) in lines.iter_mut().zip(shares) {
                        line.cross += extra_cross;
                    }
                } else {
                    line_offsets = offsets(free, lines.len(), align_content);
                }
            }
        }

        let mut main_used = 0;
        let mut cross_position = 0;

        for (number, line) in lines.iter().enumerate() {
            cross_position += line_offsets[number];

            let line_items = &items[line.items.clone()];
            let used: i32 = line_items.iter().map(|item| item.main).sum::<i32>()
                + main_gap * (line_items.len() as i32 - 1);
            main_used = main_used.max(used);

            let line_main = definite_main.unwrap_or(used);
            let spaces = offsets(line_main - used, line_items.len(), justify);

            let mut main_position = 0;
            for (position, item) in line_items.iter().enumerate() {
                main_position += spaces[position];

                let stretch = item.stretches.then_some(line.cross);
                let outer = measure(tree, item.index, axis.exact(space, item.main, stretch));

                let free_cross = line.cross - axis.cross(outer);
                let inside = match item.align {
                    Align::Start | Align::Stretch => 0,
                    // Like CSS `safe`: a terminal has no column before the first.
                    Align::End => free_cross.max(0),
                    Align::Center => free_cross.max(0) / 2,
                };

                let main_at = if reverse {
                    line_main - main_position - item.main
                } else {
                    main_position
                };

                let at = axis.size(main_at, cross_position + inside);
                place(tree, item.index, at.width, at.height);

                main_position += item.main + main_gap;
            }

            cross_position += line.cross + cross_gap;
        }

        let cross_used = (cross_position - cross_gap).max(0);
        axis.size(main_used, cross_used)
    }
}

#[cfg(test)]
mod tests {
    use super::super::testing::*;
    use super::offsets;
    use crate::engine::style::{Align, Direction, Display, Distribute, Length};
    use crate::engine::tree::{Index, Size, Tree};

    fn item(tree: &mut Tree, id: u32, value: &str) -> Index {
        let label = text(tree, id + 100, value);
        element(tree, id, Display::Block, &[label])
    }

    fn row(tree: &mut Tree, children: &[Index]) -> Index {
        element(tree, 99, Display::Flex, children)
    }

    fn x(tree: &Tree, index: Index) -> i32 {
        tree.node(index).geometry.x
    }

    fn width(tree: &Tree, index: Index) -> i32 {
        tree.node(index).geometry.outer.width
    }

    #[test]
    fn items_sit_side_by_side_at_natural_width() {
        let mut tree = Tree::default();
        let (a, b) = (item(&mut tree, 1, "aa"), item(&mut tree, 2, "bbb"));
        let root = row(&mut tree, &[a, b]);

        assert_eq!(
            measure(&mut tree, root, 20),
            Size {
                width: 20,
                height: 1
            }
        );
        assert_eq!((x(&tree, a), width(&tree, a)), (0, 2));
        assert_eq!((x(&tree, b), width(&tree, b)), (2, 3));
    }

    #[test]
    fn grow_shares_free_space_by_ratio() {
        let mut tree = Tree::default();
        let (a, b) = (item(&mut tree, 1, "a"), item(&mut tree, 2, "b"));
        tree.node_mut(a).style.extra_mut().grow = 1.0;
        tree.node_mut(b).style.extra_mut().grow = 3.0;
        let root = row(&mut tree, &[a, b]);

        measure(&mut tree, root, 22);

        assert_eq!((width(&tree, a), width(&tree, b)), (6, 16));
    }

    #[test]
    fn grow_never_loses_a_cell_to_rounding() {
        let mut tree = Tree::default();
        let items: Vec<_> = (1..=3).map(|id| item(&mut tree, id, "x")).collect();
        for &index in &items {
            tree.node_mut(index).style.extra_mut().grow = 1.0;
        }
        let root = row(&mut tree, &items);

        measure(&mut tree, root, 10);

        let total: i32 = items.iter().map(|&index| width(&tree, index)).sum();
        assert_eq!(total, 10);
    }

    #[test]
    fn max_size_freezes_an_item_and_the_rest_take_over() {
        let mut tree = Tree::default();
        let (a, b) = (item(&mut tree, 1, "a"), item(&mut tree, 2, "b"));
        for index in [a, b] {
            tree.node_mut(index).style.extra_mut().grow = 1.0;
        }
        tree.node_mut(a).style.extra_mut().max_width = Length::Cells(3);
        let root = row(&mut tree, &[a, b]);

        measure(&mut tree, root, 20);

        assert_eq!((width(&tree, a), width(&tree, b)), (3, 17));
    }

    #[test]
    fn shrink_is_weighted_by_size() {
        let mut tree = Tree::default();
        let (a, b) = (
            item(&mut tree, 1, "aaaaaaaaaa"),
            item(&mut tree, 2, "bbbbbbbbbbbbbbbbbbbb"),
        );
        let root = row(&mut tree, &[a, b]);

        measure(&mut tree, root, 15);

        assert_eq!((width(&tree, a), width(&tree, b)), (5, 10));
    }

    #[test]
    fn shrink_zero_keeps_an_item_whole() {
        let mut tree = Tree::default();
        let (a, b) = (
            item(&mut tree, 1, "aaaaaaaaaa"),
            item(&mut tree, 2, "bbbbbbbbbb"),
        );
        tree.node_mut(a).style.extra_mut().shrink = 0.0;
        let root = row(&mut tree, &[a, b]);

        measure(&mut tree, root, 12);

        assert_eq!((width(&tree, a), width(&tree, b)), (10, 2));
    }

    #[test]
    fn basis_replaces_the_natural_size() {
        let mut tree = Tree::default();
        let a = item(&mut tree, 1, "a");
        tree.node_mut(a).style.extra_mut().basis = Length::Cells(7);
        let root = row(&mut tree, &[a]);

        measure(&mut tree, root, 20);

        assert_eq!(width(&tree, a), 7);
    }

    #[test]
    fn justify_modes_place_free_space() {
        let cases = [
            (Distribute::Start, vec![0, 1, 2]),
            (Distribute::End, vec![7, 8, 9]),
            (Distribute::Center, vec![3, 4, 5]),
            (Distribute::Between, vec![0, 4, 9]),
            (Distribute::Around, vec![1, 4, 7]),
            (Distribute::Evenly, vec![1, 4, 7]),
        ];

        for (mode, expected) in cases {
            let mut tree = Tree::default();
            let items: Vec<_> = (1..=3).map(|id| item(&mut tree, id, "x")).collect();
            let root = row(&mut tree, &items);
            tree.node_mut(root).style.extra_mut().justify = mode;

            measure(&mut tree, root, 10);

            let positions: Vec<_> = items.iter().map(|&index| x(&tree, index)).collect();
            assert_eq!(positions, expected, "{mode:?}");
        }
    }

    #[test]
    fn offsets_never_spend_more_than_is_free() {
        for mode in [
            Distribute::Between,
            Distribute::Around,
            Distribute::Evenly,
            Distribute::End,
        ] {
            for free in 0..40 {
                for count in 1..7 {
                    let total: i32 = offsets(free, count, mode).iter().sum();
                    assert!(total <= free, "{mode:?} {free} {count}");
                }
            }
        }
    }

    #[test]
    fn align_places_items_on_the_cross_axis() {
        let cases = [(Align::Start, 0), (Align::Center, 2), (Align::End, 4)];

        for (align, expected) in cases {
            let mut tree = Tree::default();
            let a = item(&mut tree, 1, "x");
            let root = row(&mut tree, &[a]);
            let style = &mut tree.node_mut(root).style;
            style.height = Length::Cells(5);
            style.extra_mut().align = align;

            measure(&mut tree, root, 10);

            assert_eq!(tree.node(a).geometry.y, expected, "{align:?}");
        }
    }

    #[test]
    fn overflowing_items_stay_inside_the_first_column() {
        for align in [Align::Center, Align::End] {
            let mut tree = Tree::default();
            let a = item(&mut tree, 1, "x");
            tree.node_mut(a).style.width = Length::Cells(30);
            let root = row(&mut tree, &[a]);
            let extra = tree.node_mut(root).style.extra_mut();
            extra.direction = Direction::Column;
            extra.align = align;

            measure(&mut tree, root, 10);

            assert_eq!(tree.node(a).geometry.x, 0, "{align:?}");
        }
    }

    #[test]
    fn stretch_fills_the_cross_axis() {
        let mut tree = Tree::default();
        let a = item(&mut tree, 1, "x");
        let root = row(&mut tree, &[a]);
        tree.node_mut(root).style.height = Length::Cells(5);

        measure(&mut tree, root, 10);

        assert_eq!(tree.node(a).geometry.outer.height, 5);
    }

    #[test]
    fn stretch_leaves_explicit_sizes_alone() {
        let mut tree = Tree::default();
        let a = item(&mut tree, 1, "x");
        tree.node_mut(a).style.height = Length::Cells(2);
        let root = row(&mut tree, &[a]);
        tree.node_mut(root).style.height = Length::Cells(5);

        measure(&mut tree, root, 10);

        assert_eq!(tree.node(a).geometry.outer.height, 2);
    }

    #[test]
    fn align_self_overrides_the_container() {
        let mut tree = Tree::default();
        let (a, b) = (item(&mut tree, 1, "x"), item(&mut tree, 2, "y"));
        tree.node_mut(b).style.extra_mut().align_self = Some(Align::End);
        let root = row(&mut tree, &[a, b]);
        let style = &mut tree.node_mut(root).style;
        style.height = Length::Cells(5);
        style.extra_mut().align = Align::Start;

        measure(&mut tree, root, 10);

        assert_eq!((tree.node(a).geometry.y, tree.node(b).geometry.y), (0, 4));
    }

    #[test]
    fn wrap_moves_items_to_new_lines() {
        let mut tree = Tree::default();
        let items: Vec<_> = (1..=3).map(|id| item(&mut tree, id, "aaaa")).collect();
        let root = row(&mut tree, &items);
        tree.node_mut(root).style.extra_mut().wrap = true;

        assert_eq!(measure(&mut tree, root, 9).height, 2);
        assert_eq!(tree.node(items[1]).geometry.x, 4);
        assert_eq!(
            (
                tree.node(items[2]).geometry.x,
                tree.node(items[2]).geometry.y
            ),
            (0, 1)
        );
    }

    #[test]
    fn gaps_separate_items_and_lines() {
        let mut tree = Tree::default();
        let items: Vec<_> = (1..=3).map(|id| item(&mut tree, id, "aaaa")).collect();
        let root = row(&mut tree, &items);
        let extra = tree.node_mut(root).style.extra_mut();
        extra.wrap = true;
        extra.column_gap = 1;
        extra.row_gap = 2;

        assert_eq!(measure(&mut tree, root, 9).height, 4);
        assert_eq!(tree.node(items[1]).geometry.x, 5);
        assert_eq!(tree.node(items[2]).geometry.y, 3);
    }

    #[test]
    fn align_content_spreads_lines() {
        let mut tree = Tree::default();
        let items: Vec<_> = (1..=2).map(|id| item(&mut tree, id, "aaaa")).collect();
        let root = row(&mut tree, &items);
        let style = &mut tree.node_mut(root).style;
        style.height = Length::Cells(6);
        let extra = style.extra_mut();
        extra.wrap = true;
        extra.align = Align::Start;
        extra.align_content = Distribute::Between;

        measure(&mut tree, root, 5);

        assert_eq!(tree.node(items[1]).geometry.y, 5);
    }

    #[test]
    fn order_changes_position_not_tree_order() {
        let mut tree = Tree::default();
        let (a, b) = (item(&mut tree, 1, "a"), item(&mut tree, 2, "b"));
        tree.node_mut(a).style.extra_mut().order = 1;
        let root = row(&mut tree, &[a, b]);

        measure(&mut tree, root, 10);

        assert_eq!((x(&tree, b), x(&tree, a)), (0, 1));
    }

    #[test]
    fn reverse_runs_from_the_far_end() {
        let mut tree = Tree::default();
        let (a, b) = (item(&mut tree, 1, "aa"), item(&mut tree, 2, "b"));
        let root = row(&mut tree, &[a, b]);
        tree.node_mut(root).style.reverse = true;

        measure(&mut tree, root, 10);

        assert_eq!((x(&tree, a), x(&tree, b)), (8, 7));
    }

    #[test]
    fn columns_stack_and_grow_vertically() {
        let mut tree = Tree::default();
        let (a, b) = (item(&mut tree, 1, "a"), item(&mut tree, 2, "b"));
        tree.node_mut(b).style.extra_mut().grow = 1.0;
        let root = row(&mut tree, &[a, b]);
        let style = &mut tree.node_mut(root).style;
        style.height = Length::Cells(8);
        style.extra_mut().direction = Direction::Column;

        measure(&mut tree, root, 10);

        assert_eq!(tree.node(b).geometry.y, 1);
        assert_eq!(tree.node(b).geometry.outer.height, 7);
        assert_eq!(width(&tree, a), 10);
    }

    #[test]
    fn columns_count_the_rows_of_wrapped_text() {
        let mut tree = Tree::default();
        let (a, b) = (
            item(&mut tree, 1, "aaaa bbbb cccc"),
            item(&mut tree, 2, "end"),
        );
        let root = row(&mut tree, &[a, b]);
        tree.node_mut(root).style.extra_mut().direction = Direction::Column;

        assert_eq!(measure(&mut tree, root, 5).height, 4);
        assert_eq!(tree.node(b).geometry.y, 3);
    }

    #[test]
    fn columns_count_wrapped_rows_inside_nested_flex() {
        let mut tree = Tree::default();
        let marker = text(&mut tree, 1, "* ");
        let body = item(&mut tree, 2, "aaaa bbbb cccc");
        tree.node_mut(body).style.extra_mut().grow = 1.0;
        let list_item = element(&mut tree, 3, Display::Flex, &[marker, body]);
        let after = item(&mut tree, 4, "end");
        let root = row(&mut tree, &[list_item, after]);
        tree.node_mut(root).style.extra_mut().direction = Direction::Column;

        assert_eq!(measure(&mut tree, root, 7).height, 4);
        assert_eq!(tree.node(after).geometry.y, 3);
    }

    #[test]
    fn fit_only_shrinks_a_row_and_never_grows_it() {
        let mut tree = Tree::default();
        let a = item(&mut tree, 1, "aa");
        tree.node_mut(a).style.extra_mut().grow = 1.0;
        let inner = element(&mut tree, 2, Display::Flex, &[a]);
        tree.node_mut(inner).style.width = Length::Fit;
        let root = row(&mut tree, &[inner]);
        let extra = tree.node_mut(root).style.extra_mut();
        extra.direction = Direction::Column;
        extra.align = Align::Start;

        measure(&mut tree, root, 20);

        assert_eq!(width(&tree, a), 2);
    }

    #[test]
    fn centered_column_items_wrap_at_the_container() {
        let mut tree = Tree::default();
        let a = item(&mut tree, 1, "aaaa bbbb cccc");
        let root = row(&mut tree, &[a]);
        let extra = tree.node_mut(root).style.extra_mut();
        extra.direction = Direction::Column;
        extra.align = Align::Center;

        assert_eq!(measure(&mut tree, root, 5).height, 3);
        assert!(tree.node(a).geometry.outer.width <= 5);
    }

    #[test]
    fn column_items_do_not_shrink_below_their_content() {
        let mut tree = Tree::default();
        let (a, b) = (item(&mut tree, 1, "a"), item(&mut tree, 2, "b"));
        let root = row(&mut tree, &[a, b]);
        let style = &mut tree.node_mut(root).style;
        style.height = Length::Cells(1);
        style.extra_mut().direction = Direction::Column;

        measure(&mut tree, root, 10);

        assert_eq!(tree.node(a).geometry.outer.height, 1);
        assert_eq!(tree.node(b).geometry.y, 1);
    }

    #[test]
    fn column_height_comes_from_content_without_a_size() {
        let mut tree = Tree::default();
        let (a, b) = (item(&mut tree, 1, "a"), item(&mut tree, 2, "b"));
        let root = row(&mut tree, &[a, b]);
        tree.node_mut(root).style.extra_mut().direction = Direction::Column;

        assert_eq!(measure(&mut tree, root, 10).height, 2);
    }

    #[test]
    fn margins_count_towards_item_size() {
        let mut tree = Tree::default();
        let (a, b) = (item(&mut tree, 1, "a"), item(&mut tree, 2, "b"));
        tree.node_mut(a).style.margin.right = 3;
        let root = row(&mut tree, &[a, b]);

        measure(&mut tree, root, 20);

        assert_eq!(x(&tree, b), 4);
    }

    #[test]
    fn flex_nests_inside_flex() {
        let mut tree = Tree::default();
        let (a, b) = (item(&mut tree, 1, "a"), item(&mut tree, 2, "b"));
        let inner = element(&mut tree, 3, Display::Flex, &[a, b]);
        tree.node_mut(inner).style.extra_mut().grow = 1.0;
        let c = item(&mut tree, 4, "c");
        let root = row(&mut tree, &[inner, c]);

        measure(&mut tree, root, 20);

        assert_eq!(width(&tree, inner), 19);
        assert_eq!(x(&tree, c), 19);
    }

    #[test]
    fn an_empty_container_has_no_rows() {
        let mut tree = Tree::default();
        let root = row(&mut tree, &[]);

        assert_eq!(measure(&mut tree, root, 10).height, 0);
    }
}
