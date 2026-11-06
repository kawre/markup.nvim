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

use super::diff::Patch;
use super::inspect::NodeInfo;
use super::style::{Display, Edges, Length, Style};
use super::tree::ClientId;
use super::Timings;
use mlua::prelude::*;

#[derive(Debug, Clone, Copy, PartialEq)]
pub enum StyleProperty {
    Margin(Side, i32),
    Padding(Side, i32),
    Width(Length),
    Height(Length),
    Spacing(i32),
    Reverse(bool),
    Highlight(u32),
    Interactive(bool),
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
        }
    }
}

#[derive(Debug, Clone, PartialEq)]
pub enum Command {
    Create { id: ClientId, display: Display },
    CreateText { id: ClientId, text: String, width: i32 },
    SetText { id: ClientId, text: String, width: i32 },
    SetStyle { id: ClientId, property: StyleProperty },
    Insert { parent: ClientId, child: ClientId, before: Option<ClientId> },
    Remove { id: ClientId },
    Clear { id: ClientId },
    Resize { width: i32 },
}

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

    fn string(&mut self) -> LuaResult<String> {
        let value: LuaString = self.value()?;
        Ok(value.to_str()?.to_owned())
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
            other => return Err(LuaError::runtime(format!("unknown display {other}"))),
        })
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
            other => return Err(LuaError::runtime(format!("unknown style property {other}"))),
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
    node.raw_set("padding", encode_edges(lua, info.padding)?)?;
    node.raw_set("width", info.width.as_str())?;
    node.raw_set("height", info.height.as_str())?;
    node.raw_set("spacing", info.spacing)?;
    node.raw_set("reverse", info.reverse)?;
    node.raw_set("hl", info.hl)?;
    node.raw_set("interactive", info.interactive)?;
    node.raw_set("dirty", info.dirty)?;
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
pub fn encode(lua: &Lua, patches: &[Patch], timings: Timings) -> LuaResult<LuaTable> {
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

    let frame = lua.create_table_with_capacity(0, 4)?;
    frame.raw_set("patches", list)?;
    frame.raw_set("layout", timings.layout)?;
    frame.raw_set("paint", timings.paint)?;
    frame.raw_set("diff", timings.diff)?;
    Ok(frame)
}
