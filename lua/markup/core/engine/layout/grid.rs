//! CSS grid: fixed, auto and fractional tracks, spans and auto placement.

use super::{Constraints, Space, Strategy, measure, place, share};
use crate::engine::style::{Align, Direction, Length, Track};
use crate::engine::tree::{Index, Size, Tree};

pub struct Grid;

struct Placed {
    index: Index,
    column: usize,
    row: usize,
    column_span: usize,
    row_span: usize,
}

/// Remembers which cells are taken. It grows as implicit tracks appear.
#[derive(Default)]
struct Occupancy {
    columns: usize,
    rows: usize,
    taken: std::collections::HashSet<(usize, usize)>,
}

impl Occupancy {
    fn free(&self, placed: &Placed) -> bool {
        (placed.row..placed.row + placed.row_span).all(|row| {
            (placed.column..placed.column + placed.column_span)
                .all(|column| !self.taken.contains(&(row, column)))
        })
    }

    fn take(&mut self, placed: &Placed) {
        self.columns = self.columns.max(placed.column + placed.column_span);
        self.rows = self.rows.max(placed.row + placed.row_span);
        for row in placed.row..placed.row + placed.row_span {
            for column in placed.column..placed.column + placed.column_span {
                self.taken.insert((row, column));
            }
        }
    }
}

/// Places items: fully explicit ones first, then the rest in flow order.
fn place_items(tree: &mut Tree, node: Index, columns: usize, rows: usize, flow: Direction) -> (Vec<Placed>, Occupancy) {
    let mut children = Vec::new();
    tree.for_each_flow_child(node, false, &mut |_, child| children.push(child));

    let mut grid = Occupancy {
        columns,
        rows,
        ..Occupancy::default()
    };

    let mut placed = Vec::with_capacity(children.len());
    let mut automatic = Vec::new();

    for index in children {
        let extra = tree.node(index).style.extra();
        let (column, row) = (extra.column, extra.row);
        let item = Placed {
            index,
            column: column.map_or(0, |column| (column - 1).max(0) as usize),
            row: row.map_or(0, |row| (row - 1).max(0) as usize),
            column_span: extra.column_span.max(1) as usize,
            row_span: extra.row_span.max(1) as usize,
        };

        if column.is_some() && row.is_some() {
            grid.take(&item);
            placed.push(item);
        } else {
            automatic.push((item, column.is_some(), row.is_some()));
        }
    }

    // The flow walks one axis and wraps on the other, which has a fixed size.
    let wrap_at = match flow {
        Direction::Row => grid.columns.max(1),
        Direction::Column => grid.rows.max(1),
    };
    let (mut major, mut minor) = (0, 0);

    for (mut item, fixed_column, fixed_row) in automatic {
        let span = match flow {
            Direction::Row => item.column_span,
            Direction::Column => item.row_span,
        };

        loop {
            let (row, column) = match flow {
                Direction::Row => (major, minor),
                Direction::Column => (minor, major),
            };
            if !fixed_row {
                item.row = row;
            }
            if !fixed_column {
                item.column = column;
            }

            let fits = minor + span <= wrap_at || minor == 0;
            if fits && grid.free(&item) {
                break;
            }

            minor += 1;
            if minor >= wrap_at {
                minor = 0;
                major += 1;
            }
        }

        grid.take(&item);
        placed.push(item);
    }

    (placed, grid)
}

/// What one item asks of the tracks it covers.
struct Contribution {
    start: usize,
    span: usize,
    size: i32,
}

fn size_tracks(
    tracks: &[Track],
    count: usize,
    gap: i32,
    available: Option<i32>,
    fill: bool,
    contributions: &[Contribution],
) -> Vec<i32> {
    let track = |position: usize| tracks.get(position).copied().unwrap_or(Track::Auto);
    let flexible = available.is_some();

    // Fractions only share space that exists, without it they act like auto.
    let content_sized = |position: usize| match track(position) {
        Track::Cells(_) => false,
        Track::Auto => true,
        Track::Fr(_) => !flexible,
    };

    let mut sizes: Vec<i32> = (0..count)
        .map(|position| match track(position) {
            Track::Cells(cells) => cells,
            _ => 0,
        })
        .collect();

    for item in contributions.iter().filter(|item| item.span == 1) {
        if item.start < count && content_sized(item.start) {
            sizes[item.start] = sizes[item.start].max(item.size);
        }
    }

    // Spanning items only add what the tracks they cover are missing.
    for item in contributions.iter().filter(|item| item.span > 1) {
        let range = item.start..(item.start + item.span).min(count);
        let current: i32 = sizes[range.clone()].iter().sum::<i32>() + gap * (item.span as i32 - 1);
        let missing = item.size - current;
        let growable: Vec<usize> = range.filter(|&position| content_sized(position)).collect();
        if missing > 0 && !growable.is_empty() {
            let shares = share(missing, &vec![1.0; growable.len()]);
            for (position, extra) in growable.into_iter().zip(shares) {
                sizes[position] += extra;
            }
        }
    }

    if let Some(available) = available {
        let gaps = gap * (count as i32 - 1).max(0);
        let free = available - gaps - sizes.iter().sum::<i32>();

        if free > 0 {
            let fractions: Vec<f32> = (0..count)
                .map(|position| match track(position) {
                    Track::Fr(fraction) => fraction,
                    _ => 0.0,
                })
                .collect();

            // Without fractions, spare room goes to auto tracks.
            let weights = if fractions.iter().sum::<f32>() > 0.0 {
                fractions
            } else if fill {
                (0..count)
                    .map(|position| if track(position) == Track::Auto { 1.0 } else { 0.0 })
                    .collect()
            } else {
                vec![0.0; count]
            };

            if weights.iter().sum::<f32>() > 0.0 {
                for (size, extra) in sizes.iter_mut().zip(share(free, &weights)) {
                    *size += extra;
                }
            }
        }
    }

    sizes
}

fn starts(sizes: &[i32], gap: i32) -> Vec<i32> {
    let mut position = 0;
    sizes
        .iter()
        .map(|size| {
            let start = position;
            position += size + gap;
            start
        })
        .collect()
}

fn area(sizes: &[i32], start: usize, span: usize, gap: i32) -> i32 {
    let end = (start + span).min(sizes.len());
    sizes[start.min(end)..end].iter().sum::<i32>() + gap * (end.saturating_sub(start) as i32 - 1).max(0)
}

fn total(sizes: &[i32], gap: i32) -> i32 {
    sizes.iter().sum::<i32>() + gap * (sizes.len() as i32 - 1).max(0)
}

impl Strategy for Grid {
    fn arrange(&self, tree: &mut Tree, node: Index, space: Space) -> Size {
        let style = &tree.node(node).style;
        let extra = style.extra();

        let column_tracks = extra.columns.clone();
        let row_tracks = extra.rows.clone();
        let flow = extra.auto_flow;
        let (justify_items, align_items) = (extra.justify_items, extra.align);
        let row_gap = extra.row_gap.max(style.spacing);
        let column_gap = extra.column_gap.max(style.spacing);

        let (items, grid) = place_items(tree, node, column_tracks.len().max(1), row_tracks.len(), flow);

        let widths: Vec<Contribution> = items
            .iter()
            .map(|item| Contribution {
                start: item.column,
                span: item.column_span,
                size: measure(tree, item.index, Constraints::intrinsic(space.width)).width,
            })
            .collect();

        let available_width = space.can_wrap().then_some(space.width);
        let columns = size_tracks(
            &column_tracks,
            grid.columns,
            column_gap,
            available_width,
            !space.intrinsic,
            &widths,
        );

        let heights: Vec<Contribution> = items
            .iter()
            .map(|item| {
                let width = area(&columns, item.column, item.column_span, column_gap);
                let constraints = Constraints {
                    exact_width: Some(width),
                    ..Constraints::available(width)
                };
                Contribution {
                    start: item.row,
                    span: item.row_span,
                    size: measure(tree, item.index, constraints).height,
                }
            })
            .collect();

        let rows = size_tracks(&row_tracks, grid.rows, row_gap, space.height, true, &heights);

        let column_starts = starts(&columns, column_gap);
        let row_starts = starts(&rows, row_gap);

        for item in &items {
            let width = area(&columns, item.column, item.column_span, column_gap);
            let height = area(&rows, item.row, item.row_span, row_gap);

            let style = &tree.node(item.index).style;
            let extra = style.extra();
            let justify = extra.justify_self.unwrap_or(justify_items);
            let align = extra.align_self.unwrap_or(align_items);

            let stretch_x = justify == Align::Stretch && style.width == Length::Auto;
            let stretch_y = align == Align::Stretch && style.height == Length::Auto;

            let outer = measure(
                tree,
                item.index,
                Constraints {
                    width,
                    height: Some(height),
                    exact_width: stretch_x.then_some(width),
                    exact_height: stretch_y.then_some(height),
                    intrinsic: !stretch_x,
                    fit: !stretch_x,
                },
            );

            let inside = |align: Align, free: i32| match align {
                Align::Start | Align::Stretch => 0,
                Align::End => free,
                Align::Center => free / 2,
            };

            place(
                tree,
                item.index,
                column_starts[item.column] + inside(justify, width - outer.width),
                row_starts[item.row] + inside(align, height - outer.height),
            );
        }

        Size {
            width: total(&columns, column_gap),
            height: total(&rows, row_gap),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::super::testing::*;
    use crate::engine::style::{Align, Direction, Display, Length, Track};
    use crate::engine::tree::{Index, Tree};

    fn cell(tree: &mut Tree, id: u32, value: &str) -> Index {
        let label = text(tree, id + 100, value);
        element(tree, id, Display::Block, &[label])
    }

    fn grid(tree: &mut Tree, columns: Vec<Track>, children: &[Index]) -> Index {
        let root = element(tree, 99, Display::Grid, children);
        tree.node_mut(root).style.extra_mut().columns = columns;
        root
    }

    fn rect(tree: &Tree, index: Index) -> (i32, i32, i32, i32) {
        let geometry = &tree.node(index).geometry;
        (geometry.x, geometry.y, geometry.outer.width, geometry.outer.height)
    }

    #[test]
    fn fixed_tracks_hold_their_size() {
        let mut tree = Tree::default();
        let (a, b) = (cell(&mut tree, 1, "a"), cell(&mut tree, 2, "b"));
        let root = grid(&mut tree, vec![Track::Cells(4), Track::Cells(6)], &[a, b]);

        measure(&mut tree, root, 30);

        assert_eq!(rect(&tree, a), (0, 0, 4, 1));
        assert_eq!(rect(&tree, b), (4, 0, 6, 1));
    }

    #[test]
    fn fractions_share_what_is_left() {
        let mut tree = Tree::default();
        let items: Vec<_> = (1..=3).map(|id| cell(&mut tree, id, "x")).collect();
        let columns = vec![Track::Cells(4), Track::Fr(1.0), Track::Fr(2.0)];
        let root = grid(&mut tree, columns, &items);

        measure(&mut tree, root, 34);

        assert_eq!(rect(&tree, items[1]), (4, 0, 10, 1));
        assert_eq!(rect(&tree, items[2]), (14, 0, 20, 1));
    }

    #[test]
    fn auto_tracks_fit_their_widest_item() {
        let mut tree = Tree::default();
        let (a, b) = (cell(&mut tree, 1, "aaaa"), cell(&mut tree, 2, "b"));
        let (c, d) = (cell(&mut tree, 3, "cc"), cell(&mut tree, 4, "d"));
        let columns = vec![Track::Auto, Track::Fr(1.0)];
        let root = grid(&mut tree, columns, &[a, b, c, d]);

        measure(&mut tree, root, 20);

        assert_eq!(rect(&tree, c), (0, 1, 4, 1));
        assert_eq!(rect(&tree, d), (4, 1, 16, 1));
    }

    #[test]
    fn spare_room_goes_to_auto_tracks_without_fractions() {
        let mut tree = Tree::default();
        let (a, b) = (cell(&mut tree, 1, "a"), cell(&mut tree, 2, "b"));
        let root = grid(&mut tree, vec![Track::Auto, Track::Auto], &[a, b]);

        measure(&mut tree, root, 20);

        assert_eq!(rect(&tree, b).2, 10);
    }

    #[test]
    fn items_wrap_into_implicit_rows() {
        let mut tree = Tree::default();
        let items: Vec<_> = (1..=5).map(|id| cell(&mut tree, id, "x")).collect();
        let root = grid(&mut tree, vec![Track::Fr(1.0), Track::Fr(1.0)], &items);

        assert_eq!(measure(&mut tree, root, 10).height, 3);
        assert_eq!(rect(&tree, items[4]), (0, 2, 5, 1));
    }

    #[test]
    fn gaps_separate_tracks() {
        let mut tree = Tree::default();
        let items: Vec<_> = (1..=4).map(|id| cell(&mut tree, id, "x")).collect();
        let root = grid(&mut tree, vec![Track::Fr(1.0), Track::Fr(1.0)], &items);
        let extra = tree.node_mut(root).style.extra_mut();
        extra.column_gap = 2;
        extra.row_gap = 1;

        assert_eq!(measure(&mut tree, root, 12).height, 3);
        assert_eq!(rect(&tree, items[3]), (7, 2, 5, 1));
    }

    #[test]
    fn explicit_placement_and_spans() {
        let mut tree = Tree::default();
        let (a, b) = (cell(&mut tree, 1, "a"), cell(&mut tree, 2, "b"));
        let extra = tree.node_mut(a).style.extra_mut();
        extra.column = Some(2);
        extra.row = Some(2);
        extra.column_span = 2;
        let columns = vec![Track::Cells(3), Track::Cells(3), Track::Cells(3)];
        let root = grid(&mut tree, columns, &[a, b]);

        measure(&mut tree, root, 20);

        assert_eq!(rect(&tree, a), (3, 1, 6, 1));
        assert_eq!(rect(&tree, b), (0, 0, 3, 1));
    }

    #[test]
    fn auto_placement_skips_taken_cells() {
        let mut tree = Tree::default();
        let (a, b, c) = (cell(&mut tree, 1, "a"), cell(&mut tree, 2, "b"), cell(&mut tree, 3, "c"));
        let extra = tree.node_mut(a).style.extra_mut();
        extra.column = Some(1);
        extra.row = Some(1);
        let root = grid(&mut tree, vec![Track::Cells(2), Track::Cells(2)], &[b, c, a]);

        measure(&mut tree, root, 20);

        assert_eq!(rect(&tree, b), (2, 0, 2, 1));
        assert_eq!(rect(&tree, c), (0, 1, 2, 1));
    }

    #[test]
    fn spans_grow_auto_tracks_only_as_needed() {
        let mut tree = Tree::default();
        let wide = cell(&mut tree, 1, "aaaaaaaaaa");
        tree.node_mut(wide).style.extra_mut().column_span = 2;
        let root = grid(&mut tree, vec![Track::Auto, Track::Auto], &[wide]);
        tree.node_mut(root).style.width = Length::Fit;

        measure(&mut tree, root, 40);

        assert_eq!(rect(&tree, wide).2, 10);
    }

    #[test]
    fn column_flow_fills_columns_first() {
        let mut tree = Tree::default();
        let items: Vec<_> = (1..=3).map(|id| cell(&mut tree, id, "x")).collect();
        let root = grid(&mut tree, vec![Track::Cells(2), Track::Cells(2)], &items);
        let extra = tree.node_mut(root).style.extra_mut();
        extra.rows = vec![Track::Cells(1), Track::Cells(1)];
        extra.auto_flow = Direction::Column;

        measure(&mut tree, root, 20);

        assert_eq!(rect(&tree, items[1]), (0, 1, 2, 1));
        assert_eq!(rect(&tree, items[2]), (2, 0, 2, 1));
    }

    #[test]
    fn row_fractions_need_a_height() {
        let mut tree = Tree::default();
        let (a, b) = (cell(&mut tree, 1, "a"), cell(&mut tree, 2, "b"));
        let root = grid(&mut tree, vec![Track::Fr(1.0)], &[a, b]);
        let style = &mut tree.node_mut(root).style;
        style.height = Length::Cells(10);
        style.extra_mut().rows = vec![Track::Fr(1.0), Track::Fr(4.0)];

        measure(&mut tree, root, 10);

        assert_eq!(rect(&tree, b), (0, 2, 10, 8));
    }

    #[test]
    fn items_align_inside_their_area() {
        let mut tree = Tree::default();
        let a = cell(&mut tree, 1, "x");
        let extra = tree.node_mut(a).style.extra_mut();
        extra.justify_self = Some(Align::End);
        extra.align_self = Some(Align::Center);
        let root = grid(&mut tree, vec![Track::Cells(10)], &[a]);
        let extra = tree.node_mut(root).style.extra_mut();
        extra.rows = vec![Track::Cells(5)];

        measure(&mut tree, root, 20);

        assert_eq!(rect(&tree, a), (9, 2, 1, 1));
    }

    #[test]
    fn columns_count_wrapped_rows_inside_a_grid() {
        let mut tree = Tree::default();
        let a = cell(&mut tree, 1, "aaaa bbbb");
        let inner = grid(&mut tree, vec![Track::Fr(1.0)], &[a]);
        let label = text(&mut tree, 2, "end");
        let after = element(&mut tree, 3, Display::Block, &[label]);
        let root = element(&mut tree, 4, Display::Flex, &[inner, after]);
        tree.node_mut(root).style.extra_mut().direction = Direction::Column;

        assert_eq!(measure(&mut tree, root, 5).height, 3);
    }

    #[test]
    fn an_empty_grid_has_no_rows() {
        let mut tree = Tree::default();
        let root = grid(&mut tree, vec![Track::Fr(1.0)], &[]);

        assert_eq!(measure(&mut tree, root, 10).height, 0);
    }
}
