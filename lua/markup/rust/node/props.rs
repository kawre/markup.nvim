use crate::node::{Node, NodeKind};
use mlua::prelude::*;
use std::{cell::RefCell, collections::HashMap, rc::Rc};
use taffy::prelude::*;

pub struct LuaProps {
    base: LuaTable,
}

trait HasLength: Sized {
    fn from_lua_value(value: LuaValue) -> Self;
}
impl HasLength for LengthPercentageAuto {
    fn from_lua_value(value: LuaValue) -> Self {
        match value {
            LuaValue::Integer(n) => LengthPercentageAuto::length(n as f32),
            LuaValue::Number(n) => LengthPercentageAuto::percent(n as f32),
            LuaValue::String(s) => {
                if let Ok(str_val) = s.to_str() {
                    if str_val == "auto" {
                        LengthPercentageAuto::auto()
                    } else {
                        panic!("Unsupported string value for LengthPercentageAuto");
                    }
                } else {
                    panic!("Failed to convert Lua string");
                }
            }
            _ => panic!("Unsupported LuaValue for LengthPercentageAuto {:?}", value),
        }
    }
}
impl HasLength for LengthPercentage {
    fn from_lua_value(value: LuaValue) -> Self {
        match value {
            LuaValue::Integer(n) => LengthPercentage::length(n as f32),
            LuaValue::Number(n) => LengthPercentage::percent(n as f32),
            _ => panic!("Unsupported LuaValue for LengthPercentage"),
        }
    }
}
fn expand_lua_rect<T>(rect: LuaValue) -> Rect<T>
where
    T: HasLength + Copy,
{
    match rect {
        LuaValue::Table(t) => {
            let get_val = |idx| T::from_lua_value(t.get(idx).ok().unwrap());

            match t.len().unwrap_or(0) {
                0 => Rect {
                    left: T::from_lua_value(LuaValue::Number(0.0)),
                    right: T::from_lua_value(LuaValue::Number(0.0)),
                    top: T::from_lua_value(LuaValue::Number(0.0)),
                    bottom: T::from_lua_value(LuaValue::Number(0.0)),
                },
                1 => {
                    let val = get_val(1);
                    Rect {
                        left: val,
                        right: val,
                        top: val,
                        bottom: val,
                    }
                }
                2 => {
                    let v1 = get_val(1);
                    let v2 = get_val(2);
                    Rect {
                        top: v1,
                        bottom: v1,
                        left: v2,
                        right: v2,
                    }
                }
                3 => {
                    let v1 = get_val(1);
                    let v2 = get_val(2);
                    let v3 = get_val(3);
                    Rect {
                        top: v1,
                        left: v2,
                        right: v2,
                        bottom: v3,
                    }
                }
                _ => {
                    let v1 = get_val(1);
                    let v2 = get_val(2);
                    let v3 = get_val(3);
                    let v4 = get_val(4);
                    Rect {
                        top: v1,
                        right: v2,
                        bottom: v3,
                        left: v4,
                    }
                }
            }
        }
        LuaValue::Number(n) => {
            let val = T::from_lua_value(LuaValue::Number(n));
            Rect {
                left: val,
                right: val,
                top: val,
                bottom: val,
            }
        }
        _ => panic!("Unsupported LuaValue for Rect: {:?}", rect),
    }
}

impl LuaProps {
    pub fn new(table: LuaTable) -> Self {
        Self { base: table }
    }

    pub fn set_prop(&mut self, key: &str, value: LuaValue) -> LuaResult<()> {
        self.base.set(key, value)
    }

    pub fn get_prop(&self, key: &str) -> Option<LuaValue> {
        match self.base.get(key).unwrap() {
            LuaValue::Nil => None,
            value => Some(value),
        }
    }

    pub fn remove_prop(&mut self, key: &str) -> LuaResult<()> {
        self.base.raw_remove(key);
        Ok(())
    }

    pub fn to_style(&self) -> Style {
        let mut style = Style::default();

        // // Display
        // if let Ok(display) = self.get_prop("display") {
        //     if let LuaValue::String(s) = display {
        //         style.display = match s.to_str().unwrap() {
        //             "flex" => taffy::style::Display::Flex,
        //             "block" => taffy::style::Display::Block,
        //             "grid" => taffy::style::Display::Grid,
        //             _ => taffy::style::Display::None,
        //         };
        //     }
        // }

        // Margin
        if let Some(margin) = self.get_prop("margin") {
            style.margin = expand_lua_rect(margin);
        }
        // Margin sides
        if let Some(mt) = self.get_prop("margin_top") {
            style.margin.top = HasLength::from_lua_value(mt);
        }
        if let Some(mb) = self.get_prop("margin_bottom") {
            style.margin.bottom = HasLength::from_lua_value(mb);
        }
        if let Some(ml) = self.get_prop("margin_left") {
            style.margin.left = HasLength::from_lua_value(ml);
        }
        if let Some(mr) = self.get_prop("margin_right") {
            style.margin.right = HasLength::from_lua_value(mr);
        }

        // Padding
        if let Some(padding) = self.get_prop("padding") {
            style.padding = expand_lua_rect(padding);
        }
        // Padding sides
        if let Some(pt) = self.get_prop("padding_top") {
            style.padding.top = HasLength::from_lua_value(pt);
        }
        if let Some(pb) = self.get_prop("padding_bottom") {
            style.padding.bottom = HasLength::from_lua_value(pb);
        }
        if let Some(pl) = self.get_prop("padding_left") {
            style.padding.left = HasLength::from_lua_value(pl);
        }
        if let Some(pr) = self.get_prop("padding_right") {
            style.margin.right = HasLength::from_lua_value(pr);
        }

        // Justify
        // if let Some(justify) = self.get_prop("justify") {
        //     // Map your markup.box.justify to taffy::style::JustifyContent here
        //     // style.justify_items = AlignItems::from(AlignItems::Stretch);
        // }
        //
        // // Align
        // if let Some(align) = self.get_prop("align") {
        //     // Map your markup.box.align to taffy::style::AlignItems here
        // }

        // Sizing
        // if let Ok(sizing) = self.get_prop("sizing") {
        //     if let LuaValue::String(s) = sizing {
        //         style.box_sizing = match s.to_str().unwrap() {
        //             "outer" => BoxSizing::BorderBox,
        //             "inner" => BoxSizing::ContentBox,
        //             _ => BoxSizing::ContentBox,
        //         };
        //     }
        // }

        // Direction
        // let vertical = self.get_prop("vertical").unwrap_or(false);
        // let horizontal = self.get_prop("horizontal").unwrap_or(false);
        // let reverse = self.get_prop("reverse").unwrap_or(false);

        // style.flex_direction = match (vertical, horizontal, reverse) {
        //     (true, _, false) => FlexDirection::Column,
        //     (true, _, true) => FlexDirection::ColumnReverse,
        //     (_, true, false) => FlexDirection::Row,
        //     (_, true, true) => FlexDirection::RowReverse,
        //     _ => FlexDirection::Row,
        // };

        style
    }
}
