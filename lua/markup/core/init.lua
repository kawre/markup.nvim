---@class markup.core
local core = {}

core.lookups = {
	-- Object
	object = "markup.core.object",

	-- Node
	node = "markup.core.node",
	-- Text
	text = "markup.core.node.text",
	pad = "markup.core.node.text.padding",

	-- Fiber
	fiber = "markup.core.fiber",

	-- TabPage
	tabpage = "markup.core.tabpage",

	-- Layout
	layout = "markup.core.layout",

	-- Element
	element = "markup.core.node.element",
	anchor = "markup.core.node.element.inline.anchor",
	code = "markup.core.node.element.inline.code",
	italic = "markup.core.node.element.inline.italic",
	mark = "markup.core.node.element.inline.mark",
	strike = "markup.core.node.element.inline.strike",
	strong = "markup.core.node.element.inline.strong",
	sub = "markup.core.node.element.inline.sub",
	sup = "markup.core.node.element.inline.sup",
	underline = "markup.core.node.element.inline.underline",
	list = "markup.core.node.element.block.list",
	olist = "markup.core.node.element.block.list.ordered",
	listitem = "markup.core.node.element.block.list.item",
	pre = "markup.core.node.element.block.pre",
	tree = "markup.core.node.element.block.tree",

	-- Inline
	inline = "markup.core.node.element.inline",
	-- Block
	block = "markup.core.node.element.block",
	-- Flex
	box = "markup.core.node.element.flex",
	flex = "markup.core.node.element.flex",
	hflex = "markup.core.node.element.flex.horizontal",
	-- Grid
	grid = "markup.core.node.element.grid",

	-- Window
	window = "markup.core.window",
	renderer = "markup.core.window.renderer",
	rendererline = "markup.core.window.renderer.line",
	rendererbuilder = "markup.core.window.renderer.line.builder",

	-- Component
	component = "markup.core.element.component",

	-- Parser
	parser = "markup.core.parser",

	-- Utils
	["if"] = "markup.core.node.if",
	fragment = "markup.core.node.fragment",

	element2 = "markup.core.element",
}

return core
