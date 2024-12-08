local Enum = require("markup.collection.enum")
local log = require("markup.logger") ---@diagnostic disable-line: unused-local

---@class markup.core.enum : markup.Enum
local enum = Enum()

enum.Inline = {
	INLINE = "markup.core.node.element.inline",
	ANCHOR = "markup.core.node.element.inline.anchor",
	CODE = "markup.core.node.element.inline.code",
	ITALIC = "markup.core.node.element.inline.italic",
	MARK = "markup.core.node.element.inline.mark",
	STRIKE = "markup.core.node.element.inline.strike",
	STRONG = "markup.core.node.element.inline.strong",
	SUB = "markup.core.node.element.inline.sub",
	SUP = "markup.core.node.element.inline.sup",
	UNDERLINE = "markup.core.node.element.inline.underline",
}

enum.Block = {
	BLOCK = "markup.core.node.element.block",
	LIST = "markup.core.node.element.block.list",
	OLIST = "markup.core.node.element.block.list.ordered",
	LISTITEM = "markup.core.node.element.block.list.item",
	PRE = "markup.core.node.element.block.pre",
}

enum.Flex = {
	FLEX = "markup.core.node.element.flex",
	BOX = "markup.core.node.element.flex",
	HFLEX = "markup.core.node.element.flex.horizontal",
}

enum.Element = {
	ELEMENT = "markup.core.node.element",
	enum.Inline,
	enum.Block,
	enum.Flex,
}

enum.Text = {
	TEXT = "markup.core.node.text",
	PAD = "markup.core.node.text.padding",
}

enum.Node = {
	NODE = "markup.core.node",
	enum.Element,
	enum.Text,
}

enum.CreateElement = {
	CREATE_ELEMENT = "markup.core.create.element",
	CREATE_ROOT = "markup.core.create.element.root",
	CREATE_COMPONENT = "markup.core.create.element.component",
}

enum.CreateFiber = {
	CREATE_FIBER = "markup.core.create.fiber",
	CREATE_FIBER_ROOT = "markup.core.create.fiber.root",
	CREATE_FIBER_FROM_ELEMENT = "markup.core.create.fiber.from_element",
}

enum.Create = {
	CREATE_FRAGMENT = "markup.core.create.fragment",
	CREATE_RENDERER_ROOT = "markup.core.create.renderer.root",
	enum.CreateElement,
	enum.CreateFiber,
}

enum.Renderer = {
	RENDERER = "markup.core.window.renderer",
	RENDERERLINE = "markup.core.window.renderer.line",
	RENDERERBUILDER = "markup.core.window.renderer.line.builder",
}

enum.Window = {
	WINDOW = "markup.core.window",
	enum.Renderer,
}

enum.Collection = {
	ENUM = "markup.collection.enum",
	SWITCH = "markup.collection.switch",
	ARRAY = "markup.collection.array",
}

enum.Lookup = {
	RECONCILER = "markup.core.reconciler",
	TABPAGE = "markup.core.tabpage",
	OBJECT = "markup.core.object",
	PARSER = "markup.core.parser",
	LAYOUT = "markup.core.layout",
	enum.Node,
	enum.Create,
	enum.Window,
	enum.Collection,
}

return enum
