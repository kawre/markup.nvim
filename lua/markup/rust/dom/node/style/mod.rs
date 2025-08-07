mod lua;

pub use lua::*;

pub struct NodeStyle {
    pub display: Display,
    pub flex_direction: FlexDirection,
    pub flex_wrap: FlexWrap,
    pub align_items: AlignItems,
    pub align_self: AlignSelf,
    pub justify_content: JustifyContent,
    pub width: AvailableSpace,
    pub height: AvailableSpace,
    pub min_width: AvailableSpace,
    pub min_height: AvailableSpace,
    pub max_width: AvailableSpace,
    pub max_height: AvailableSpace,
    pub padding_left: f32,
    pub padding_right: f32,
    pub padding_top: f32,
    pub padding_bottom: f32,
    pub margin_left: f32,
    pub margin_right: f32,
    pub margin_top: f32,
    pub margin_bottom: f32,
}
