//! Style values attached to nodes. Plain data, with no knowledge of Lua.

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
        matches!(self, Display::Block)
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
}
