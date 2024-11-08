---@class markup.core
local core = {}

core.lookups = {
    -- Object
    Object = "markup.core.object",

    -- Node
    Node = "markup.core.node",

    -- Text
    Text = "markup.core.node.text",
    Pad = "markup.core.node.text.padding",

    -- Line
    Line = "markup.core.line",

    -- Element
    Element = "markup.core.node.element",
    Inline = "markup.core.node.element.inline",
    Block = "markup.core.node.element.block",
    Box = "markup.core.node.element.block.box",

    -- Window
    Window = "markup.core.window",
    Renderer = "markup.core.window.renderer",
}

return core
