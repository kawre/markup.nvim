local log = require("markup.logger") ---@diagnostic disable-line: unused-local

---@class markup.core
local core = {}

core.node_lookup = {
	node = "markup.core.node",
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
	inline = "markup.core.node.element.inline",
	block = "markup.core.node.element.block",
	box = "markup.core.node.element.flex",
	flex = "markup.core.node.element.flex",
	hflex = "markup.core.node.element.flex.horizontal",
	grid = "markup.core.node.element.grid",
	["if"] = "markup.core.node.if",
	fragment = "markup.core.node.fragment",
	text = "markup.core.node.text",
	pad = "markup.core.node.text.padding",
}

core.default_lookups = {
	fiber = "markup.core.fiber",
	tabpage = "markup.core.tabpage",
	object = "markup.core.object",
	parser = "markup.core.parser",
	window = "markup.core.window",
	renderer = "markup.core.window.renderer",
	rendererline = "markup.core.window.renderer.line",
	rendererbuilder = "markup.core.window.renderer.line.builder",
	layout = "markup.core.layout",
	create_element = "markup.core.create.element",
	create_root = "markup.core.create.root",
	create_fiber_root = "markup.core.create.fiber.root",
	create_component = "markup.core.create.component",
}

core.lookups = vim.tbl_extend( --
	"error",
	core.default_lookups,
	core.node_lookup
)

---@type markup.core
return setmetatable(core, {
	__index = function(t, k)
		local u = require("markup.utils")
		return u.lookup(t.lookups, k)
	end,
})
