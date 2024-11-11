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

    -- TabPage
    TabPage = "markup.core.tabpage",

    -- Layout
    Layout = "markup.core.layout",

    -- Element
    Element = "markup.core.node.element",

    -- Inline
    Inline = "markup.core.node.element.inline",
    Anchor = "markup.core.node.element.inline.anchor",
    Code = "markup.core.node.element.inline.code",
    Italic = "markup.core.node.element.inline.italic",
    Mark = "markup.core.node.element.inline.mark",
    Strike = "markup.core.node.element.inline.strike",
    Strong = "markup.core.node.element.inline.strong",
    Sub = "markup.core.node.element.inline.sub",
    Sup = "markup.core.node.element.inline.sup",
    Underline = "markup.core.node.element.inline.underline",

    -- Block
    Block = "markup.core.node.element.block",
    List = "markup.core.node.element.block.list",
    OrderedList = "markup.core.node.element.block.list.ordered",
    ListItem = "markup.core.node.element.block.list.item",

    -- Box
    Box = "markup.core.node.element.box",

    -- Window
    Window = "markup.core.window",
    Renderer = "markup.core.window.renderer",
    RendererLine = "markup.core.window.renderer.line",
}

return core
