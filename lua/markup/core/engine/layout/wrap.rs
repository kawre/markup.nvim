//! Line breaking for a run of inline content.
//!
//! The whole run wraps as one piece of text: a line can break inside any span,
//! and a word split across two spans stays together. Each text node then holds
//! the fragments it was cut into, and each inline element the area it covers
//! on every line, which is what paint draws highlights over.

use super::{Constraints, measure, place};
use crate::engine::style::Display;
use crate::engine::tree::{Fragment, Index, Size, Tree};

#[derive(Clone, Copy, PartialEq, Eq)]
enum Kind {
    Word,
    Space,
    Newline,
    /// Margin or padding of an inline element, which cannot be broken.
    Gap,
    /// An element that is not text, such as a block inside an inline.
    Atomic,
    /// A wide character, such as a CJK ideograph: as CSS breaks lines, a
    /// line can break before and after each one.
    Ideograph,
}

#[derive(Clone, Copy)]
struct Piece {
    kind: Kind,
    node: Index,
    start: usize,
    end: usize,
    width: i32,
    height: i32,
    /// Rows from its top to the line it sits on, as CSS aligns inline boxes to
    /// a baseline: the bottom of a row of text.
    baseline: i32,
    /// Offset of the node's origin from the run's origin.
    base: (i32, i32),
    /// Whether a line may break right after it, as after the hyphen of
    /// "x-y", where CSS breaks a word.
    breaks_after: bool,
}

/// An inline element and the pieces inside it.
struct Span {
    node: Index,
    first: usize,
    last: usize,
    base: (i32, i32),
}

#[derive(Default)]
struct Tokens {
    pieces: Vec<Piece>,
    spans: Vec<Span>,
    /// Parts of inlines split around blocks: added to what earlier parts
    /// cover, rather than replacing it.
    parts: Vec<Span>,
    /// Every node visited, so all of them end up clean.
    nodes: Vec<Index>,
}

/// Width of each character of a text, in order.
fn char_widths<'a>(tree: &'a Tree, node: Index) -> impl Iterator<Item = (usize, char, i32)> + 'a {
    let node = tree.node(node);
    let mut cells = node.cells.iter().flat_map(|cells| cells.iter().copied());
    node.text.char_indices().map(move |(byte, character)| {
        let width = if character.is_ascii() {
            1
        } else {
            cells.next().map_or(1, i32::from)
        };
        (byte, character, width)
    })
}

fn tokenize_text(tree: &Tree, node: Index, base: (i32, i32), pieces: &mut Vec<Piece>) {
    let piece = |kind, start, end, width| Piece {
        kind,
        node,
        start,
        end,
        width,
        height: 1,
        baseline: 1,
        base,
        breaks_after: false,
    };

    let mut current: Option<Piece> = None;
    let mut characters = char_widths(tree, node).peekable();
    while let Some((byte, character, width)) = characters.next() {
        let end = byte + character.len_utf8();
        let kind = match character {
            '\n' => Kind::Newline,
            ' ' | '\t' => Kind::Space,
            _ if width > 1 => Kind::Ideograph,
            _ => Kind::Word,
        };

        match &mut current {
            Some(open) if open.kind == kind && !matches!(kind, Kind::Newline | Kind::Ideograph) => {
                open.end = end;
                open.width += width;
            }
            _ => {
                pieces.extend(current.take());
                let width = if kind == Kind::Newline { 0 } else { width };
                current = Some(piece(kind, byte, end, width));
            }
        }

        // As CSS breaks lines: after a hyphen inside a word, unless a digit
        // or another hyphen follows.
        let hyphen = matches!(character, '-' | '\u{2010}' | '\u{2013}');
        let next = characters.peek().map(|&(_, next, _)| next);
        let word_follows = next.is_some_and(|next| {
            !next.is_ascii_digit()
                && !matches!(next, ' ' | '\t' | '\n' | '-' | '\u{2010}' | '\u{2013}')
        });
        if hyphen
            && kind == Kind::Word
            && word_follows
            && let Some(mut open) = current.take()
        {
            open.breaks_after = true;
            pieces.push(open);
        }
    }
    pieces.extend(current);
}

fn has_only_inline_children(tree: &mut Tree, node: Index) -> bool {
    let mut inline = true;
    tree.for_each_flow_child(node, false, &mut |tree, child| {
        inline &= tree.node(child).display.is_inline();
    });
    inline
}

fn tokenize(tree: &mut Tree, node: Index, base: (i32, i32), width: i32, tokens: &mut Tokens) {
    tokens.nodes.push(node);

    if tree.node(node).display == Display::Text {
        tokenize_text(tree, node, base, &mut tokens.pieces);
        return;
    }

    // As CSS: an inline-block is one piece on the line, as wide as its content
    // up to the line, and never split across lines.
    let inline_block = super::is_inline_block(&tree.node(node).style);
    if inline_block || !has_only_inline_children(tree, node) {
        let constraints = if inline_block {
            Constraints::fit_content(width)
        } else {
            Constraints::intrinsic(width)
        };
        let outer = measure(tree, node, constraints);
        let entry = tree.node(node);
        let baseline = if inline_block {
            // As CSS: the line of its last row, or the bottom of its margin when
            // it has none or cuts off what does not fit.
            let style = &entry.style;
            if entry.geometry.content.height > 0 && !style.extra().scrolls {
                style.margin.top + style.inner().top + entry.geometry.content.height
            } else {
                outer.height
            }
        } else {
            // Aligned with the top of the line, as before.
            1
        };
        tokens.nodes.pop();
        tokens.pieces.push(Piece {
            kind: Kind::Atomic,
            node,
            start: 0,
            end: 0,
            width: outer.width,
            height: outer.height,
            baseline,
            base,
            breaks_after: false,
        });
        return;
    }

    let style = &tree.node(node).style;
    let (margin, padding) = (style.margin, style.inner());
    let reverse = style.reverse;

    let gap = |width: i32| Piece {
        kind: Kind::Gap,
        node,
        start: 0,
        end: 0,
        width,
        height: 1,
        baseline: 1,
        base,
        breaks_after: false,
    };

    if margin.left > 0 {
        tokens.pieces.push(gap(margin.left));
    }

    let first = tokens.pieces.len();
    if padding.left > 0 {
        tokens.pieces.push(gap(padding.left));
    }

    let inner = (
        base.0 + margin.left + padding.left,
        base.1 + margin.top + padding.top,
    );

    let mut children = Vec::new();
    tree.for_each_flow_child(node, reverse, &mut |_, child| children.push(child));
    for child in children {
        tokenize(tree, child, inner, width, tokens);
    }

    if padding.right > 0 {
        tokens.pieces.push(gap(padding.right));
    }

    tokens.spans.push(Span {
        node,
        first,
        last: tokens.pieces.len(),
        base,
    });

    if margin.right > 0 {
        tokens.pieces.push(gap(margin.right));
    }
}

/// A piece after line breaking. Words wider than a line become several.
#[derive(Clone, Copy)]
struct Placed {
    source: usize,
    start: usize,
    end: usize,
    x: i32,
    y: i32,
    width: i32,
    baseline: i32,
}

struct Breaker {
    limit: i32,
    x: i32,
    y: i32,
    line_height: i32,
    widest: i32,
    placed: Vec<Placed>,
    /// The first piece of the current line, and how far it reaches above and
    /// below its baseline.
    line_start: usize,
    ascent: i32,
    descent: i32,
}

impl Breaker {
    /// Puts each piece of the line on its baseline.
    fn finish_line(&mut self) {
        for placed in &mut self.placed[self.line_start..] {
            placed.y = self.y + (self.ascent - placed.baseline).max(0);
        }
        self.line_start = self.placed.len();
    }

    fn new_line(&mut self) {
        self.finish_line();
        self.y += self.line_height.max(1);
        self.x = 0;
        self.line_height = 0;
        self.ascent = 0;
        self.descent = 0;
    }

    fn put(&mut self, source: usize, piece: &Piece) {
        self.placed.push(Placed {
            source,
            start: piece.start,
            end: piece.end,
            x: self.x,
            y: self.y,
            width: piece.width,
            baseline: piece.baseline,
        });
        self.x += piece.width;
        self.widest = self.widest.max(self.x);
        self.ascent = self.ascent.max(piece.baseline);
        self.descent = self.descent.max(piece.height - piece.baseline);
        self.line_height = self.line_height.max(self.ascent + self.descent);
    }

    fn put_all(&mut self, pieces: &[Piece], from: usize, to: usize) {
        for (offset, piece) in pieces[from..to].iter().enumerate() {
            self.put(from + offset, piece);
        }
    }

    /// Breaks a word that cannot fit on any line, one character at a time.
    fn put_split(&mut self, tree: &Tree, source: usize, piece: &Piece) {
        let mut run: Option<Piece> = None;

        for (byte, character, width) in char_widths(tree, piece.node) {
            if byte < piece.start || byte >= piece.end {
                continue;
            }

            let used = run.map_or(0, |run| run.width);
            if self.x + used + width > self.limit && self.x + used > 0 {
                if let Some(run) = run.take() {
                    self.put(source, &run);
                }
                self.new_line();
            }

            let end = byte + character.len_utf8();
            match &mut run {
                Some(open) => {
                    open.end = end;
                    open.width += width;
                }
                None => {
                    run = Some(Piece {
                        start: byte,
                        end,
                        width,
                        ..*piece
                    });
                }
            }
        }

        if let Some(run) = run {
            self.put(source, &run);
        }
    }
}

/// Where what cannot be broken, starting at `from`, ends: at a space or a line
/// break, after a piece a line may break after, and around an ideograph,
/// which stands on its own.
fn unbreakable_end(pieces: &[Piece], from: usize) -> usize {
    let mut end = from;
    while end < pieces.len() {
        let piece = &pieces[end];
        let alone = piece.kind == Kind::Ideograph;
        if matches!(piece.kind, Kind::Space | Kind::Newline) || (alone && end > from) {
            break;
        }
        end += 1;
        if alone || piece.breaks_after {
            break;
        }
    }
    end
}

fn break_lines(tree: &Tree, pieces: &[Piece], limit: i32, split_words: bool) -> Breaker {
    let mut breaker = Breaker {
        limit,
        x: 0,
        y: 0,
        line_height: 0,
        widest: 0,
        placed: Vec::with_capacity(pieces.len()),
        line_start: 0,
        ascent: 0,
        descent: 0,
    };

    let mut position = 0;
    while position < pieces.len() {
        let piece = &pieces[position];

        match piece.kind {
            Kind::Newline => {
                breaker.placed.push(Placed {
                    source: position,
                    start: piece.start,
                    end: piece.start,
                    x: breaker.x,
                    y: breaker.y,
                    width: 0,
                    baseline: 1,
                });
                breaker.new_line();
                position += 1;
            }
            Kind::Space => {
                // Spaces survive inside a line, and vanish at a break.
                let next = pieces[position + 1..]
                    .iter()
                    .position(|piece| piece.kind != Kind::Space)
                    .map_or(pieces.len(), |offset| position + 1 + offset);
                // What follows up to where a line could break next: an
                // ideograph stands alone.
                let unbroken: i32 = pieces[next..unbreakable_end(pieces, next)]
                    .iter()
                    .map(|piece| piece.width)
                    .sum();
                let spaces: i32 = pieces[position..next].iter().map(|piece| piece.width).sum();

                let ends_line = next == pieces.len() || pieces[next].kind == Kind::Newline;
                let fits = breaker.x + spaces + unbroken <= limit;

                if ends_line {
                    // Nothing follows on this line, so trailing spaces only
                    // stay when they fit.
                    if breaker.x + spaces <= limit {
                        breaker.put_all(pieces, position, next);
                    }
                } else if fits || breaker.x == 0 {
                    breaker.put_all(pieces, position, next);
                } else {
                    breaker.new_line();
                }
                position = next;
            }
            Kind::Word | Kind::Gap | Kind::Atomic | Kind::Ideograph => {
                let end = unbreakable_end(pieces, position);
                let width: i32 = pieces[position..end].iter().map(|piece| piece.width).sum();

                if breaker.x > 0 && breaker.x + width > limit {
                    breaker.new_line();
                }

                for (offset, piece) in pieces[position..end].iter().enumerate() {
                    if piece.kind == Kind::Word && width > limit && split_words {
                        breaker.put_split(tree, position + offset, piece);
                    } else {
                        breaker.put(position + offset, piece);
                    }
                }
                position = end;
            }
        }
    }

    breaker.finish_line();
    breaker
}

/// What a run of inline content holds: nodes, and the edges of an inline that
/// is split around the blocks inside it, as CSS splits one.
#[derive(Debug, Clone, Copy)]
pub enum RunItem {
    Node(Index),
    /// Where a part of a split inline starts. Only the first part has its
    /// left margin, border and padding. `base` is the inline's origin from
    /// the run's origin.
    Open {
        node: Index,
        first: bool,
        base: (i32, i32),
    },
    /// Where a part ends. Only the last part has its right edges.
    Close {
        node: Index,
        last: bool,
    },
}

fn gap_piece(node: Index, base: (i32, i32), width: i32) -> Piece {
    Piece {
        kind: Kind::Gap,
        node,
        start: 0,
        end: 0,
        width,
        height: 1,
        baseline: 1,
        base,
        breaks_after: false,
    }
}

/// Flows a run of nodes, breaking lines past `limit`; see `flow_items`.
pub fn flow(tree: &mut Tree, run: &[Index], limit: i32, available: i32, split_words: bool) -> Size {
    let items: Vec<RunItem> = run.iter().map(|&node| RunItem::Node(node)).collect();
    flow_items(tree, &items, limit, available, split_words)
}

/// Lays out a run of inline nodes in `limit` cells at the origin of the run.
/// Flows a run of inline nodes, breaking lines past `limit`. Whatever cannot
/// flow, such as a block among them, is laid out for `available`, which a run
/// that never breaks still needs: `limit` is then unbounded, and a child as
/// wide as its parent would be that wide too. Without `split_words`, a word
/// longer than a line runs past it whole.
pub fn flow_items(
    tree: &mut Tree,
    items: &[RunItem],
    limit: i32,
    available: i32,
    split_words: bool,
) -> Size {
    let mut tokens = Tokens::default();
    // The split inlines open at this point.
    struct Part {
        /// Where its pieces start.
        start: usize,
        /// Its content's origin, and its own, from the run's origin.
        inner: (i32, i32),
        base: (i32, i32),
    }
    let mut open: Vec<Part> = Vec::new();
    for &item in items {
        match item {
            RunItem::Node(node) => {
                let base = open.last().map_or((0, 0), |part| part.inner);
                tokenize(tree, node, base, available, &mut tokens);
            }
            RunItem::Open { node, first, base } => {
                let style = &tree.node(node).style;
                let (margin, padding) = (style.margin, style.inner());
                if first && margin.left > 0 {
                    tokens.pieces.push(gap_piece(node, base, margin.left));
                }
                let start = tokens.pieces.len();
                if first && padding.left > 0 {
                    tokens.pieces.push(gap_piece(node, base, padding.left));
                }
                let inner = (
                    base.0 + margin.left + padding.left,
                    base.1 + margin.top + padding.top,
                );
                open.push(Part { start, inner, base });
            }
            RunItem::Close { node, last } => {
                let Some(Part { start, base, .. }) = open.pop() else {
                    continue;
                };
                let style = &tree.node(node).style;
                let (margin, padding) = (style.margin, style.inner());
                if last && padding.right > 0 {
                    tokens.pieces.push(gap_piece(node, base, padding.right));
                }
                tokens.parts.push(Span {
                    node,
                    first: start,
                    last: tokens.pieces.len(),
                    base,
                });
                if last && margin.right > 0 {
                    tokens.pieces.push(gap_piece(node, base, margin.right));
                }
            }
        }
    }

    let breaker = break_lines(tree, &tokens.pieces, limit, split_words);
    let size = Size {
        width: breaker.widest,
        height: breaker.y
            + breaker
                .line_height
                .max(if breaker.placed.is_empty() { 0 } else { 1 }),
    };

    // Text fragments, merging what stayed together on a line.
    let mut fragments: Vec<(Index, Fragment)> = Vec::with_capacity(breaker.placed.len());
    for placed in &breaker.placed {
        let piece = &tokens.pieces[placed.source];
        match piece.kind {
            Kind::Atomic => {
                place(
                    tree,
                    piece.node,
                    placed.x - piece.base.0,
                    placed.y - piece.base.1,
                );
                continue;
            }
            Kind::Gap => continue,
            Kind::Word | Kind::Space | Kind::Newline | Kind::Ideograph => {}
        }
        if placed.width == 0 {
            continue;
        }

        let fragment = Fragment {
            x: placed.x - piece.base.0,
            y: placed.y - piece.base.1,
            width: placed.width,
            start: placed.start as u32,
            end: placed.end as u32,
        };

        match fragments.last_mut() {
            Some((node, last))
                if *node == piece.node
                    && last.y == fragment.y
                    && last.x + last.width == fragment.x
                    && last.end == fragment.start =>
            {
                last.width += fragment.width;
                last.end = fragment.end;
            }
            _ => fragments.push((piece.node, fragment)),
        }
    }

    for &node in &tokens.nodes {
        let entry = tree.node_mut(node);
        entry.geometry.x = 0;
        entry.geometry.y = 0;
        entry.geometry.content = size;
        entry.geometry.outer = size;
        entry.geometry.constraints = None;
        entry.dirty = false;
        entry.fragments = Some(Vec::new());
    }

    for (node, fragment) in fragments {
        tree.node_mut(node)
            .fragments
            .get_or_insert_default()
            .push(fragment);
    }

    // What each inline element covers on each line, for its highlight. A
    // part of a split inline adds to what its earlier parts cover.
    let spans = tokens.spans.iter().map(|span| (span, false));
    for (span, part) in spans.chain(tokens.parts.iter().map(|span| (span, true))) {
        let mut rows: Vec<Fragment> = Vec::new();
        for placed in &breaker.placed {
            if placed.source < span.first || placed.source >= span.last || placed.width == 0 {
                continue;
            }
            let (x, y) = (placed.x - span.base.0, placed.y - span.base.1);
            match rows.last_mut() {
                Some(row) if row.y == y => row.width = x + placed.width - row.x,
                _ => rows.push(Fragment {
                    x,
                    y,
                    width: placed.width,
                    start: 0,
                    end: 0,
                }),
            }
        }
        let entry = tree.node_mut(span.node);
        if part {
            entry.fragments.get_or_insert_default().extend(rows);
        } else {
            entry.fragments = Some(rows);
        }
    }

    size
}

#[cfg(test)]
mod tests {
    use super::super::testing::*;
    use crate::engine::style::{Display, Length, WhiteSpace};
    use crate::engine::tree::{Index, Tree};

    fn paragraph(tree: &mut Tree, value: &str) -> (Index, Index) {
        let label = text(tree, 1, value);
        (element(tree, 2, Display::Block, &[label]), label)
    }

    fn pieces(tree: &Tree, node: Index) -> Vec<(i32, i32, String)> {
        let entry = tree.node(node);
        entry
            .fragments
            .iter()
            .flatten()
            .map(|f| {
                (
                    f.x,
                    f.y,
                    entry.text[f.start as usize..f.end as usize].to_string(),
                )
            })
            .collect()
    }

    #[test]
    fn text_that_fits_stays_on_the_plain_path() {
        let mut tree = Tree::default();
        let (root, label) = paragraph(&mut tree, "short");

        assert_eq!(measure(&mut tree, root, 20).height, 1);
        assert!(tree.node(label).fragments.is_none());
    }

    #[test]
    fn breaks_at_spaces() {
        let mut tree = Tree::default();
        let (root, label) = paragraph(&mut tree, "the quick brown fox");

        assert_eq!(measure(&mut tree, root, 10).height, 2);
        assert_eq!(
            pieces(&tree, label),
            vec![
                (0, 0, "the quick".to_string()),
                (0, 1, "brown fox".to_string()),
            ]
        );
    }

    #[test]
    fn the_space_at_a_break_disappears() {
        let mut tree = Tree::default();
        let (root, label) = paragraph(&mut tree, "aaaa bbbb");

        measure(&mut tree, root, 4);

        assert_eq!(
            pieces(&tree, label),
            vec![(0, 0, "aaaa".to_string()), (0, 1, "bbbb".to_string()),]
        );
    }

    #[test]
    fn splits_words_wider_than_the_line() {
        let mut tree = Tree::default();
        let (root, label) = paragraph(&mut tree, "abcdefghij");

        assert_eq!(measure(&mut tree, root, 4).height, 3);
        assert_eq!(
            pieces(&tree, label),
            vec![
                (0, 0, "abcd".to_string()),
                (0, 1, "efgh".to_string()),
                (0, 2, "ij".to_string()),
            ]
        );
    }

    #[test]
    fn honours_newlines() {
        let mut tree = Tree::default();
        let (root, label) = paragraph(&mut tree, "one\ntwo");

        assert_eq!(measure(&mut tree, root, 20).height, 2);
        assert_eq!(
            pieces(&tree, label),
            vec![(0, 0, "one".to_string()), (0, 1, "two".to_string()),]
        );
    }

    #[test]
    fn nowrap_keeps_one_line_but_still_honours_newlines() {
        let mut tree = Tree::default();
        let (root, _) = paragraph(&mut tree, "the quick brown fox");
        tree.node_mut(root).style.extra_mut().white_space = Some(WhiteSpace::Nowrap);
        assert_eq!(measure(&mut tree, root, 5).height, 1);

        let mut tree = Tree::default();
        let (root, _) = paragraph(&mut tree, "the quick\nbrown fox");
        tree.node_mut(root).style.extra_mut().white_space = Some(WhiteSpace::Nowrap);
        assert_eq!(measure(&mut tree, root, 5).height, 2);
    }

    #[test]
    fn white_space_is_inherited_and_can_be_undone() {
        let mut tree = Tree::default();
        let label = text(&mut tree, 1, "aaaa bbbb");
        let inner = element(&mut tree, 2, Display::Block, &[label]);
        let root = element(&mut tree, 3, Display::Block, &[inner]);
        tree.node_mut(root).style.extra_mut().white_space = Some(WhiteSpace::Nowrap);

        assert_eq!(measure(&mut tree, root, 5).height, 1);

        tree.node_mut(inner).style.extra_mut().white_space = Some(WhiteSpace::Normal);
        tree.mark_subtree_dirty(inner);

        assert_eq!(measure(&mut tree, root, 5).height, 2);
    }

    #[test]
    fn spans_wrap_as_one_text() {
        let mut tree = Tree::default();
        let a = text(&mut tree, 1, "aaa ");
        let a_span = element(&mut tree, 2, Display::Inline, &[a]);
        let b = text(&mut tree, 3, "bbb ccc");
        let b_span = element(&mut tree, 4, Display::Inline, &[b]);
        let root = element(&mut tree, 5, Display::Block, &[a_span, b_span]);

        assert_eq!(measure(&mut tree, root, 8).height, 2);
        assert_eq!(
            pieces(&tree, b),
            vec![(4, 0, "bbb".to_string()), (0, 1, "ccc".to_string()),]
        );

        let rows: Vec<_> = tree
            .node(b_span)
            .fragments
            .iter()
            .flatten()
            .map(|f| (f.x, f.y, f.width))
            .collect();
        assert_eq!(rows, vec![(4, 0, 3), (0, 1, 3)]);
    }

    #[test]
    fn a_word_across_two_spans_stays_together() {
        let mut tree = Tree::default();
        let a = text(&mut tree, 1, "xx foo");
        let b = text(&mut tree, 2, "bar");
        let root = element(&mut tree, 3, Display::Block, &[a, b]);

        measure(&mut tree, root, 7);

        assert_eq!(
            pieces(&tree, a),
            vec![(0, 0, "xx".to_string()), (0, 1, "foo".to_string())]
        );
        assert_eq!(pieces(&tree, b), vec![(3, 1, "bar".to_string())]);
    }

    #[test]
    fn wide_characters_count_their_real_width() {
        let mut tree = Tree::default();
        let label = text(&mut tree, 1, "你好世界");
        let entry = tree.node_mut(label);
        entry.text_width = 8;
        entry.cells = Some(vec![2, 2, 2, 2].into_boxed_slice());
        let root = element(&mut tree, 2, Display::Block, &[label]);

        assert_eq!(measure(&mut tree, root, 4).height, 2);
        assert_eq!(
            pieces(&tree, label),
            vec![(0, 0, "你好".to_string()), (0, 1, "世界".to_string()),]
        );
    }

    #[test]
    fn rewraps_when_the_width_changes() {
        let mut tree = Tree::default();
        let (root, _) = paragraph(&mut tree, "aaaa bbbb cccc");

        assert_eq!(measure(&mut tree, root, 5).height, 3);
        assert_eq!(measure(&mut tree, root, 20).height, 1);
        assert_eq!(measure(&mut tree, root, 10).height, 2);
    }

    #[test]
    fn padding_narrows_the_line() {
        let mut tree = Tree::default();
        let (root, _) = paragraph(&mut tree, "aaaa bbbb");
        tree.node_mut(root).style.padding.left = 2;

        assert_eq!(measure(&mut tree, root, 10).height, 2);
    }

    #[test]
    fn wraps_at_an_explicit_width() {
        let mut tree = Tree::default();
        let (root, _) = paragraph(&mut tree, "aaaa bbbb");
        tree.node_mut(root).style.width = Length::Cells(5);

        assert_eq!(measure(&mut tree, root, 40).height, 2);
    }

    #[test]
    fn a_flex_item_wraps_at_its_final_width() {
        let mut tree = Tree::default();
        let long = text(&mut tree, 1, "aaaa bbbb cccc dddd");
        let item = element(&mut tree, 2, Display::Block, &[long]);
        let short = text(&mut tree, 3, "side");
        let side = element(&mut tree, 4, Display::Block, &[short]);
        tree.node_mut(side).style.extra_mut().shrink = 0.0;
        let root = element(&mut tree, 5, Display::Flex, &[item, side]);

        assert_eq!(measure(&mut tree, root, 14).height, 2);
    }

    #[test]
    fn nodes_end_up_clean_so_later_changes_reach_the_root() {
        let mut tree = Tree::default();
        let (root, label) = paragraph(&mut tree, "aaaa bbbb");
        measure(&mut tree, root, 5);

        assert!(!tree.node(label).dirty);
        tree.mark_dirty(label);
        assert!(tree.node(root).dirty);
    }
}
