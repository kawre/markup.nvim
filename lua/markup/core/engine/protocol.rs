//! Wire format between Lua and the engine.
//!
//! Lua appends commands to one flat array and sends it once per frame, so a
//! frame costs a single boundary crossing however much changed:
//!
//! ```text
//! { opcode, arg, arg, opcode, arg, ... }
//! ```
//!
//! The opcodes mirror `lua/markup/view/protocol.lua`. Patches return as tables
//! of strings and flat integer arrays, with highlights as interned ids.

use super::Timings;
use super::diff::Patch;
use super::inspect::NodeInfo;
use super::style::{
    Align, Border, Direction, Display, Distribute, Edges, Length, Overflow, Position, Style,
    TextOverflow, Track, WhiteSpace,
};
use super::tree::ClientId;
use mlua::prelude::*;

#[derive(Debug, Clone, PartialEq)]
pub enum StyleProperty {
    Margin(Side, i32),
    Padding(Side, i32),
    Width(Length),
    Height(Length),
    Spacing(i32),
    Reverse(bool),
    Highlight(u32),
    Interactive(bool),
    Direction(Direction),
    Wrap(bool),
    Justify(Distribute),
    Align(Align),
    AlignContent(Distribute),
    AlignSelf(Option<Align>),
    RowGap(i32),
    ColumnGap(i32),
    Grow(f32),
    Shrink(f32),
    Basis(Length),
    Order(i32),
    MinWidth(Length),
    MaxWidth(Length),
    MinHeight(Length),
    MaxHeight(Length),
    Position(Position),
    Top(Option<i32>),
    Right(Option<i32>),
    Bottom(Option<i32>),
    Left(Option<i32>),
    Z(i32),
    AutoFlow(Direction),
    JustifyItems(Align),
    JustifySelf(Option<Align>),
    GridColumn(Option<i32>),
    GridRow(Option<i32>),
    ColumnSpan(i32),
    RowSpan(i32),
    WhiteSpace(Option<WhiteSpace>),
    OverflowY(Overflow),
    OverflowX(Overflow),
    Snap(Option<bool>),
    Inert(bool),
    TextOverflow(Option<TextOverflow>),
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Side {
    Top,
    Right,
    Bottom,
    Left,
}

impl Side {
    fn of(self, edges: &mut Edges) -> &mut i32 {
        match self {
            Side::Top => &mut edges.top,
            Side::Right => &mut edges.right,
            Side::Bottom => &mut edges.bottom,
            Side::Left => &mut edges.left,
        }
    }
}

impl StyleProperty {
    /// Whether the property only changes how a node is painted or answers
    /// input, never where anything is: the next frame paints it anew anyway.
    pub fn paint_only(&self) -> bool {
        matches!(
            self,
            StyleProperty::Highlight(_)
                | StyleProperty::Interactive(_)
                | StyleProperty::Inert(_)
                | StyleProperty::Snap(_)
                | StyleProperty::TextOverflow(_)
        )
    }

    pub fn apply(self, style: &mut Style) {
        match self {
            StyleProperty::Margin(side, value) => *side.of(&mut style.margin) = value,
            StyleProperty::Padding(side, value) => *side.of(&mut style.padding) = value,
            StyleProperty::Width(value) => style.width = value,
            StyleProperty::Height(value) => style.height = value,
            StyleProperty::Spacing(value) => style.spacing = value,
            StyleProperty::Reverse(value) => style.reverse = value,
            StyleProperty::Highlight(value) => style.hl = value,
            StyleProperty::Interactive(value) => style.interactive = value,
            StyleProperty::Direction(value) => style.extra_mut().direction = value,
            StyleProperty::Wrap(value) => style.extra_mut().wrap = value,
            StyleProperty::Justify(value) => style.extra_mut().justify = value,
            StyleProperty::Align(value) => style.extra_mut().align = value,
            StyleProperty::AlignContent(value) => style.extra_mut().align_content = value,
            StyleProperty::AlignSelf(value) => style.extra_mut().align_self = value,
            StyleProperty::RowGap(value) => style.extra_mut().row_gap = value,
            StyleProperty::ColumnGap(value) => style.extra_mut().column_gap = value,
            StyleProperty::Grow(value) => style.extra_mut().grow = value,
            StyleProperty::Shrink(value) => style.extra_mut().shrink = value,
            StyleProperty::Basis(value) => style.extra_mut().basis = value,
            StyleProperty::Order(value) => style.extra_mut().order = value,
            StyleProperty::MinWidth(value) => style.extra_mut().min_width = value,
            StyleProperty::MaxWidth(value) => style.extra_mut().max_width = value,
            StyleProperty::MinHeight(value) => style.extra_mut().min_height = value,
            StyleProperty::MaxHeight(value) => style.extra_mut().max_height = value,
            StyleProperty::Position(value) => style.extra_mut().position = value,
            StyleProperty::Top(value) => style.extra_mut().inset.top = value,
            StyleProperty::Right(value) => style.extra_mut().inset.right = value,
            StyleProperty::Bottom(value) => style.extra_mut().inset.bottom = value,
            StyleProperty::Left(value) => style.extra_mut().inset.left = value,
            StyleProperty::Z(value) => style.extra_mut().z = value,
            StyleProperty::AutoFlow(value) => style.extra_mut().auto_flow = value,
            StyleProperty::JustifyItems(value) => style.extra_mut().justify_items = value,
            StyleProperty::JustifySelf(value) => style.extra_mut().justify_self = value,
            StyleProperty::GridColumn(value) => style.extra_mut().column = value,
            StyleProperty::GridRow(value) => style.extra_mut().row = value,
            StyleProperty::ColumnSpan(value) => style.extra_mut().column_span = value,
            StyleProperty::RowSpan(value) => style.extra_mut().row_span = value,
            StyleProperty::WhiteSpace(value) => style.extra_mut().white_space = value,
            StyleProperty::OverflowY(value) => style.extra_mut().set_overflow(None, Some(value)),
            StyleProperty::OverflowX(value) => style.extra_mut().set_overflow(Some(value), None),
            StyleProperty::Snap(value) => style.extra_mut().snap = value,
            StyleProperty::Inert(value) => style.extra_mut().inert = value,
            StyleProperty::TextOverflow(value) => style.extra_mut().text_overflow = value,
        }
    }
}

#[derive(Debug, Clone, PartialEq)]
pub enum Command {
    Create {
        id: ClientId,
        display: Display,
    },
    CreateText {
        id: ClientId,
        text: String,
        width: i32,
    },
    SetText {
        id: ClientId,
        text: String,
        width: i32,
    },
    SetStyle {
        id: ClientId,
        property: StyleProperty,
    },
    Insert {
        parent: ClientId,
        child: ClientId,
        before: Option<ClientId>,
    },
    Remove {
        id: ClientId,
    },
    Clear {
        id: ClientId,
    },
    Resize {
        width: i32,
    },
    SetTracks {
        id: ClientId,
        axis: Direction,
        tracks: Vec<Track>,
    },
    SetBorder {
        id: ClientId,
        border: Option<Border>,
    },
    /// Widths of the non ASCII characters of a text, as digits.
    SetCells {
        id: ClientId,
        cells: Vec<u8>,
    },
}

/// Stands for "unset" in optional values, because the array cannot hold nil.
const UNSET: i32 = -1_000_000;

/// Reads values from the flat command array.
struct Reader<'a> {
    ops: &'a LuaTable,
    position: usize,
}

impl Reader<'_> {
    fn value<T: FromLua>(&mut self) -> LuaResult<T> {
        self.position += 1;
        self.ops.raw_get(self.position)
    }

    fn int(&mut self) -> LuaResult<i32> {
        self.value()
    }

    fn id(&mut self) -> LuaResult<ClientId> {
        self.value()
    }

    /// Text that is not UTF-8 comes through with replacement characters, as
    /// one string that cannot be read must not cost the rest of the frame.
    fn string(&mut self) -> LuaResult<String> {
        let value: LuaString = self.value()?;
        Ok(String::from_utf8_lossy(&value.as_bytes()).into_owned())
    }

    /// Text arrives with its width, or `-1` when it is ASCII.
    fn text(&mut self) -> LuaResult<(String, i32)> {
        let text = self.string()?;
        let width = self.int()?;
        let width = if width < 0 { text.len() as i32 } else { width };
        Ok((text, width))
    }

    fn length(&mut self) -> LuaResult<Length> {
        let value: f64 = self.value()?;
        Ok(match value {
            -1.0 => Length::Auto,
            -2.0 => Length::Fit,
            -3.0 => Length::Full,
            share if share > 0.0 && share < 1.0 => Length::Fraction(share as f32),
            cells => Length::Cells(cells as i32),
        })
    }

    fn display(&mut self) -> LuaResult<Display> {
        Ok(match self.int()? {
            1 => Display::Block,
            2 => Display::Inline,
            3 => Display::Contents,
            4 => Display::Flex,
            5 => Display::Grid,
            other => return Err(LuaError::runtime(format!("unknown display {other}"))),
        })
    }

    fn optional(&mut self) -> LuaResult<Option<i32>> {
        let value = self.int()?;
        Ok((value != UNSET).then_some(value))
    }

    fn align(&mut self) -> LuaResult<Option<Align>> {
        Ok(match self.int()? {
            0 => None,
            1 => Some(Align::Start),
            2 => Some(Align::End),
            3 => Some(Align::Center),
            4 => Some(Align::Stretch),
            other => return Err(LuaError::runtime(format!("unknown align {other}"))),
        })
    }

    fn required_align(&mut self) -> LuaResult<Align> {
        Ok(self.align()?.unwrap_or_default())
    }

    fn distribute(&mut self) -> LuaResult<Distribute> {
        Ok(match self.int()? {
            1 => Distribute::Start,
            2 => Distribute::End,
            3 => Distribute::Center,
            4 => Distribute::Between,
            5 => Distribute::Around,
            6 => Distribute::Evenly,
            7 => Distribute::Stretch,
            other => return Err(LuaError::runtime(format!("unknown distribution {other}"))),
        })
    }

    fn direction(&mut self) -> LuaResult<Direction> {
        Ok(if self.int()? == 0 {
            Direction::Row
        } else {
            Direction::Column
        })
    }

    fn position(&mut self) -> LuaResult<Position> {
        Ok(match self.int()? {
            0 => Position::Static,
            1 => Position::Relative,
            2 => Position::Absolute,
            other => return Err(LuaError::runtime(format!("unknown position {other}"))),
        })
    }

    fn tracks(&mut self) -> LuaResult<Vec<Track>> {
        let count = self.int()?;
        (0..count)
            .map(|_| {
                let kind = self.int()?;
                let value: f32 = self.value()?;
                Ok(match kind {
                    0 => Track::Auto,
                    1 => Track::Cells(value as i32),
                    2 => Track::Fr(value),
                    other => return Err(LuaError::runtime(format!("unknown track {other}"))),
                })
            })
            .collect()
    }

    /// Eight characters, a mask of sides, a highlight and a flag. Characters
    /// other than eight mean no border, and the rest is read all the same, as
    /// leaving it would read it as the commands that follow.
    fn border(&mut self) -> LuaResult<Option<Border>> {
        let characters: Vec<char> = self.string()?.chars().collect();
        let sides = self.int()?;
        let hl = self.value()?;
        let outside_background = self.int()? != 0;
        let Ok(chars) = <[char; 8]>::try_from(characters) else {
            return Ok(None);
        };

        Ok(Some(Border {
            chars,
            top: sides & 1 != 0,
            right: sides & 2 != 0,
            bottom: sides & 4 != 0,
            left: sides & 8 != 0,
            hl,
            outside_background,
        }))
    }

    fn style_property(&mut self) -> LuaResult<StyleProperty> {
        let side = |index: i32| match index % 4 {
            1 => Side::Top,
            2 => Side::Right,
            3 => Side::Bottom,
            _ => Side::Left,
        };

        let property = self.int()?;
        Ok(match property {
            1..=4 => StyleProperty::Margin(side(property), self.int()?),
            5..=8 => StyleProperty::Padding(side(property), self.int()?),
            9 => StyleProperty::Width(self.length()?),
            10 => StyleProperty::Height(self.length()?),
            11 => StyleProperty::Spacing(self.int()?),
            12 => StyleProperty::Reverse(self.int()? != 0),
            13 => StyleProperty::Highlight(self.value()?),
            14 => StyleProperty::Interactive(self.int()? != 0),
            15 => StyleProperty::Direction(self.direction()?),
            16 => StyleProperty::Wrap(self.int()? != 0),
            17 => StyleProperty::Justify(self.distribute()?),
            18 => StyleProperty::Align(self.required_align()?),
            19 => StyleProperty::AlignContent(self.distribute()?),
            20 => StyleProperty::AlignSelf(self.align()?),
            21 => StyleProperty::RowGap(self.int()?),
            22 => StyleProperty::ColumnGap(self.int()?),
            23 => StyleProperty::Grow(self.value()?),
            24 => StyleProperty::Shrink(self.value()?),
            25 => StyleProperty::Basis(self.length()?),
            26 => StyleProperty::Order(self.int()?),
            27 => StyleProperty::MinWidth(self.length()?),
            28 => StyleProperty::MaxWidth(self.length()?),
            29 => StyleProperty::MinHeight(self.length()?),
            30 => StyleProperty::MaxHeight(self.length()?),
            31 => StyleProperty::Position(self.position()?),
            32 => StyleProperty::Top(self.optional()?),
            33 => StyleProperty::Right(self.optional()?),
            34 => StyleProperty::Bottom(self.optional()?),
            35 => StyleProperty::Left(self.optional()?),
            36 => StyleProperty::Z(self.int()?),
            37 => StyleProperty::AutoFlow(self.direction()?),
            38 => StyleProperty::JustifyItems(self.required_align()?),
            39 => StyleProperty::JustifySelf(self.align()?),
            40 => StyleProperty::GridColumn(self.optional()?),
            41 => StyleProperty::GridRow(self.optional()?),
            42 => StyleProperty::ColumnSpan(self.int()?),
            43 => StyleProperty::RowSpan(self.int()?),
            44 => StyleProperty::WhiteSpace(match self.optional()? {
                None => None,
                Some(0) => Some(WhiteSpace::Normal),
                Some(_) => Some(WhiteSpace::Nowrap),
            }),
            45 => StyleProperty::OverflowY(self.overflow()?),
            46 => StyleProperty::OverflowX(self.overflow()?),
            47 => StyleProperty::Snap(self.optional()?.map(|value| value != 0)),
            48 => StyleProperty::Inert(self.int()? != 0),
            49 => StyleProperty::TextOverflow(match self.value::<LuaValue>()? {
                LuaValue::Table(marker) => {
                    let text: String = marker.raw_get(1)?;
                    let width = marker.raw_get(2)?;
                    let digits: String = marker.raw_get(3)?;
                    let cells = digits
                        .bytes()
                        .map(|digit| digit.saturating_sub(b'0'))
                        .collect();
                    Some(TextOverflow { text, width, cells })
                }
                _ => None,
            }),
            other => return Err(LuaError::runtime(format!("unknown style property {other}"))),
        })
    }

    fn overflow(&mut self) -> LuaResult<Overflow> {
        Ok(match self.int()? {
            0 => Overflow::Visible,
            1 => Overflow::Hidden,
            _ => Overflow::Clip,
        })
    }

    fn command(&mut self) -> LuaResult<Command> {
        let opcode = self.int()?;
        Ok(match opcode {
            1 => Command::Create {
                id: self.id()?,
                display: self.display()?,
            },
            2 => {
                let id = self.id()?;
                let (text, width) = self.text()?;
                Command::CreateText { id, text, width }
            }
            3 => {
                let id = self.id()?;
                let (text, width) = self.text()?;
                Command::SetText { id, text, width }
            }
            4 => Command::SetStyle {
                id: self.id()?,
                property: self.style_property()?,
            },
            5 => {
                let parent = self.id()?;
                let child = self.id()?;
                let before = self.id()?;
                Command::Insert {
                    parent,
                    child,
                    before: (before != 0).then_some(before),
                }
            }
            6 => Command::Remove { id: self.id()? },
            7 => Command::Clear { id: self.id()? },
            8 => Command::Resize { width: self.int()? },
            9 => Command::SetTracks {
                id: self.id()?,
                axis: self.direction()?,
                tracks: self.tracks()?,
            },
            11 => Command::SetBorder {
                id: self.id()?,
                border: self.border()?,
            },
            10 => {
                let id = self.id()?;
                let digits = self.string()?;
                Command::SetCells {
                    id,
                    cells: digits
                        .bytes()
                        .map(|digit| digit.saturating_sub(b'0'))
                        .collect(),
                }
            }
            other => return Err(LuaError::runtime(format!("unknown opcode {other}"))),
        })
    }
}

/// Decodes the first `len` values of `ops` and passes each command to `apply`.
pub fn decode(
    ops: &LuaTable,
    len: usize,
    mut apply: impl FnMut(Command) -> LuaResult<()>,
) -> LuaResult<()> {
    let mut reader = Reader { ops, position: 0 };
    while reader.position < len {
        apply(reader.command()?)?;
    }
    // A command read with more or fewer values than were written would have
    // shifted everything after it, quietly setting whatever the values landed
    // on. It ends anywhere but at the end then.
    if reader.position != len {
        return Err(LuaError::runtime(format!(
            "commands out of step: read {} values of {}",
            reader.position, len
        )));
    }
    Ok(())
}

fn encode_edges(lua: &Lua, edges: Edges) -> LuaResult<LuaTable> {
    lua.create_sequence_from([edges.top, edges.right, edges.bottom, edges.left])
}

/// Builds the table devtools read for one node.
pub fn encode_node(lua: &Lua, info: &NodeInfo) -> LuaResult<LuaTable> {
    let node = lua.create_table_with_capacity(0, 16)?;
    node.raw_set("id", info.id)?;
    node.raw_set("parent", info.parent)?;
    node.raw_set("display", info.display)?;
    node.raw_set("text", info.text.as_deref())?;
    node.raw_set("children", info.children)?;
    if let Some(rect) = info.rect {
        node.raw_set("x", rect.x)?;
        node.raw_set("y", rect.y)?;
        node.raw_set("outer_width", rect.width)?;
        node.raw_set("outer_height", rect.height)?;
    }
    node.raw_set("content_width", info.content.width)?;
    node.raw_set("content_height", info.content.height)?;
    node.raw_set("margin", encode_edges(lua, info.margin)?)?;
    node.raw_set("border", encode_edges(lua, info.border)?)?;
    node.raw_set("padding", encode_edges(lua, info.padding)?)?;
    node.raw_set("width", info.width.as_str())?;
    node.raw_set("height", info.height.as_str())?;
    node.raw_set("spacing", info.spacing)?;
    node.raw_set("reverse", info.reverse)?;
    node.raw_set("hl", info.hl)?;
    node.raw_set("interactive", info.interactive)?;
    node.raw_set("dirty", info.dirty)?;
    node.raw_set("position", info.position)?;
    Ok(node)
}

/// Builds the frame table returned to Lua.
///
/// ```lua
/// {
///   patches = { { first, last, lines = { ... }, marks = { row, start, end, hl, ... } } },
///   layout = 0.1, paint = 0.2, diff = 0.3,
/// }
/// ```
/// Errors are the commands that could not be applied, such as one for a node
/// that is gone, each said once.
pub fn encode(
    lua: &Lua,
    patches: &[Patch],
    timings: Timings,
    errors: &[String],
) -> LuaResult<LuaTable> {
    let list = lua.create_table_with_capacity(patches.len(), 0)?;

    for (index, patch) in patches.iter().enumerate() {
        let lines = lua.create_table_with_capacity(patch.lines.len(), 0)?;
        let marks = lua.create_table()?;
        let mut position = 0;

        for (offset, line) in patch.lines.iter().enumerate() {
            lines.raw_set(offset + 1, lua.create_string(&line.text)?)?;
            for mark in &line.marks {
                let row = (patch.first + offset) as u32;
                for value in [row, mark.start, mark.end, mark.hl] {
                    position += 1;
                    marks.raw_set(position, value)?;
                }
            }
        }

        let entry = lua.create_table_with_capacity(2, 2)?;
        entry.raw_set(1, patch.first)?;
        entry.raw_set(2, patch.last)?;
        entry.raw_set("lines", lines)?;
        entry.raw_set("marks", marks)?;
        list.raw_set(index + 1, entry)?;
    }

    let frame = lua.create_table_with_capacity(0, 5)?;
    frame.raw_set("patches", list)?;
    frame.raw_set("layouts", timings.layouts)?;
    frame.raw_set("layout", timings.layout)?;
    frame.raw_set("paint", timings.paint)?;
    frame.raw_set("diff", timings.diff)?;
    if !errors.is_empty() {
        frame.raw_set(
            "errors",
            lua.create_sequence_from(errors.iter().map(String::as_str))?,
        )?;
    }
    Ok(frame)
}
