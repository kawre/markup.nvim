//! Style values attached to nodes. Plain data, with no knowledge of Lua.

use std::sync::LazyLock;

/// How a node takes part in layout.
///
/// To add a layout mode: add a variant here, implement [`super::layout::Strategy`]
/// in a new file, and register it in `layout::strategy`.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum Display {
    #[default]
    Block,
    Inline,
    Text,
    Flex,
    Grid,
    /// Transparent group: its children flow as if they belonged to its parent.
    Contents,
}

impl Display {
    /// Whether the node sits on the current line instead of starting a new one.
    pub fn is_inline(self) -> bool {
        matches!(self, Display::Inline | Display::Text)
    }

    /// Whether an `auto` width takes all the available space.
    pub fn fills_width(self) -> bool {
        matches!(self, Display::Block | Display::Flex | Display::Grid)
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Default)]
pub enum Length {
    #[default]
    Auto,
    Fit,
    Full,
    Cells(i32),
    /// Share of the available space, between 0 and 1.
    Fraction(f32),
}

impl Length {
    /// Resolves against `available`, or returns `None` when the content decides.
    pub fn resolve(self, available: i32) -> Option<i32> {
        match self {
            Length::Auto | Length::Fit => None,
            Length::Full => Some(available),
            Length::Cells(cells) => Some(cells),
            Length::Fraction(share) => Some((available as f32 * share).ceil() as i32),
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub struct Edges {
    pub top: i32,
    pub right: i32,
    pub bottom: i32,
    pub left: i32,
}

impl Edges {
    pub fn horizontal(self) -> i32 {
        self.left + self.right
    }

    pub fn vertical(self) -> i32 {
        self.top + self.bottom
    }
}

/// How an item sits on an axis of its container.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum Align {
    Start,
    End,
    Center,
    #[default]
    Stretch,
}

/// How free space is shared around a row of items or lines.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum Distribute {
    #[default]
    Start,
    End,
    Center,
    Between,
    Around,
    Evenly,
    Stretch,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum Direction {
    #[default]
    Row,
    Column,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum Position {
    #[default]
    Static,
    Relative,
    Absolute,
}

/// A border drawn inside the margin, around the padding.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Border {
    /// Top left, top, top right, right, bottom right, bottom, bottom left, left.
    pub chars: [char; 8],
    pub top: bool,
    pub right: bool,
    pub bottom: bool,
    pub left: bool,
    /// Highlight id of the border itself.
    pub hl: u32,
    /// Keep the background off the border. Half block borders need it, as
    /// their characters paint the half of the cell that belongs to the box.
    pub outside_background: bool,
}

/// Whether text may break onto new lines. Inherited, like in CSS.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum WhiteSpace {
    #[default]
    Normal,
    Nowrap,
}

/// Size of a grid track.
#[derive(Debug, Clone, Copy, PartialEq, Default)]
pub enum Track {
    #[default]
    Auto,
    Cells(i32),
    Fr(f32),
}

/// Offsets from the containing block, unset sides stay `None`.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub struct Inset {
    pub top: Option<i32>,
    pub right: Option<i32>,
    pub bottom: Option<i32>,
    pub left: Option<i32>,
}

/// Rarely used style. Most nodes are text and inline spans, so this lives
/// behind a box that plain nodes never allocate.
#[derive(Debug, Clone, PartialEq)]
pub struct Extra {
    /// Unset inherits from the parent.
    pub white_space: Option<WhiteSpace>,

    pub border: Option<Border>,

    /// Cut what does not fit the height, so a height can be animated.
    pub clip: bool,

    // Containers.
    pub direction: Direction,
    pub wrap: bool,
    pub justify: Distribute,
    pub align: Align,
    pub align_content: Distribute,
    pub row_gap: i32,
    pub column_gap: i32,

    // Flex items.
    pub align_self: Option<Align>,
    pub grow: f32,
    pub shrink: f32,
    pub basis: Length,
    pub order: i32,

    // Size limits.
    pub min_width: Length,
    pub max_width: Length,
    pub min_height: Length,
    pub max_height: Length,

    // Positioning.
    pub position: Position,
    pub inset: Inset,
    pub z: i32,

    // Grid containers.
    pub columns: Vec<Track>,
    pub rows: Vec<Track>,
    pub auto_flow: Direction,
    pub justify_items: Align,

    // Grid items.
    pub column: Option<i32>,
    pub row: Option<i32>,
    pub column_span: i32,
    pub row_span: i32,
    pub justify_self: Option<Align>,
}

impl Default for Extra {
    fn default() -> Self {
        Extra {
            white_space: None,
            border: None,
            clip: false,
            direction: Direction::Row,
            wrap: false,
            justify: Distribute::Start,
            align: Align::Stretch,
            align_content: Distribute::Stretch,
            row_gap: 0,
            column_gap: 0,
            align_self: None,
            grow: 0.0,
            shrink: 1.0,
            basis: Length::Auto,
            order: 0,
            min_width: Length::Auto,
            max_width: Length::Auto,
            min_height: Length::Auto,
            max_height: Length::Auto,
            position: Position::Static,
            inset: Inset::default(),
            z: 0,
            columns: Vec::new(),
            rows: Vec::new(),
            auto_flow: Direction::Row,
            justify_items: Align::Stretch,
            column: None,
            row: None,
            column_span: 1,
            row_span: 1,
            justify_self: None,
        }
    }
}

static DEFAULT_EXTRA: LazyLock<Extra> = LazyLock::new(Extra::default);

#[derive(Debug, Clone, PartialEq, Default)]
pub struct Style {
    pub margin: Edges,
    pub padding: Edges,
    pub width: Length,
    pub height: Length,
    /// Rows left between block children.
    pub spacing: i32,
    pub reverse: bool,
    /// Highlight id, interned on the Lua side. Zero means none.
    pub hl: u32,
    /// Whether `Engine::node_at` can stop at this node.
    pub interactive: bool,
    extra: Option<Box<Extra>>,
}

impl Style {
    pub fn extra(&self) -> &Extra {
        self.extra.as_deref().unwrap_or(&DEFAULT_EXTRA)
    }

    pub fn extra_mut(&mut self) -> &mut Extra {
        self.extra.get_or_insert_default()
    }

    pub fn border(&self) -> Option<&Border> {
        self.extra.as_deref().and_then(|extra| extra.border.as_ref())
    }

    /// Cells the border takes on each side.
    pub fn border_edges(&self) -> Edges {
        self.border().map_or(Edges::default(), |border| Edges {
            top: border.top as i32,
            right: border.right as i32,
            bottom: border.bottom as i32,
            left: border.left as i32,
        })
    }

    /// Everything between the margin and the content: border and padding.
    pub fn inner(&self) -> Edges {
        let (padding, border) = (self.padding, self.border_edges());
        Edges {
            top: padding.top + border.top,
            right: padding.right + border.right,
            bottom: padding.bottom + border.bottom,
            left: padding.left + border.left,
        }
    }

    /// Hot paths read this for every node, and most have no extra style.
    pub fn position(&self) -> Position {
        self.extra.as_deref().map_or(Position::Static, |extra| extra.position)
    }

    /// How far `position: relative` moves a node from where flow put it.
    pub fn relative_offset(&self) -> (i32, i32) {
        if self.position() != Position::Relative {
            return (0, 0);
        }
        let inset = self.extra().inset;
        (
            inset.left.or(inset.right.map(|right| -right)).unwrap_or(0),
            inset.top.or(inset.bottom.map(|bottom| -bottom)).unwrap_or(0),
        )
    }
}
