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
	Extmark = "markup.core.node.text.extmark",

	-- TabPage
	TabPage = "markup.core.tabpage",

	-- Layout
	Layout = "markup.core.layout",

	-- Element
	Element = "markup.core.node.element",
	Anchor = "markup.core.node.element.inline.anchor",
	Code = "markup.core.node.element.inline.code",
	Italic = "markup.core.node.element.inline.italic",
	Mark = "markup.core.node.element.inline.mark",
	Strike = "markup.core.node.element.inline.strike",
	Strong = "markup.core.node.element.inline.strong",
	Sub = "markup.core.node.element.inline.sub",
	Sup = "markup.core.node.element.inline.sup",
	Underline = "markup.core.node.element.inline.underline",
	List = "markup.core.node.element.block.list",
	OList = "markup.core.node.element.block.list.ordered",
	ListItem = "markup.core.node.element.block.list.item",
	Pre = "markup.core.node.element.block.pre",
	Tree = "markup.core.node.element.block.tree",

	-- Inline
	Inline = "markup.core.node.element.inline",
	-- Block
	Block = "markup.core.node.element.block",
	-- Flex
	Box = "markup.core.node.element.flex",
	Flex = "markup.core.node.element.flex",
	HFlex = "markup.core.node.element.flex.horizontal",
	-- Grid
	Grid = "markup.core.node.element.grid",

	-- Window
	Window = "markup.core.window",
	Renderer = "markup.core.window.renderer",
	RendererLine = "markup.core.window.renderer.line",

	-- Component
	Component = "markup.core.component",

	-- Parser
	Parser = "markup.core.parser",

	-- Utils
	If = "markup.core.node.if",
	Fragment = "markup.core.node.fragment",
	Brake = "markup.core.node.brake",
}

return core
