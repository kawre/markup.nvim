---@class markup.core
local core = {}

core.lookups = {
	-- Object
	Object = "markup.core.object",

	-- Text
	Text = "markup.core.text",
	Padding = "markup.core.text.padding",

	-- Line
	Line = "markup.core.line",

	-- Element
	Element = "markup.core.element",
	Inline = "markup.core.element.inline",
	Block = "markup.core.element.block",
	Box = "markup.core.element.box",

	-- Window
	Window = "markup.core.window",
	Renderer = "markup.core.window.renderer",
}

return core
