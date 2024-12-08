local log = require("markup.logger") ---@diagnostic disable-line: unused-local
local Node = require("markup.core.enum").Node
local Lookup = require("markup.core.enum").Lookup
local markup = require("markup.core")

---@class markup.enum : markup.Enum
local enum = markup.Enum()

enum.Node = {
	BLOCK = Node.BLOCK,
	LIST = Node.LIST,
	LISTITEM = Node.LISTITEM,
	OLIST = Node.OLIST,
	FLEX = Node.FLEX,
	HFLEX = Node.HFLEX,
	BOX = Node.BOX,
	GRID = Node.GRID,
	INLINE = Node.INLINE,
	ANCHOR = Node.ANCHOR,
	CODE = Node.CODE,
	ITALIC = Node.ITALIC,
	MARK = Node.MARK,
	STRIKE = Node.STRIKE,
	STRONG = Node.STRONG,
	SUB = Node.SUB,
	SUP = Node.SUP,
	UNDERLINE = Node.UNDERLINE,
	TEXT = Node.TEXT,
	PAD = Node.PAD,
}

enum.CreateNode = enum:map(enum.Node, function(v)
	local core = require("markup.core")
	return function(props)
		return core.create_element(require(v), props)
	end
end)

enum.Collection = {
	SWITCH = Lookup.SWITCH,
	ARRAY = Lookup.ARRAY,
}

enum.Lookup = {
	enum.CreateNode,
	enum.Collection,
	LAYOUT = Lookup.LAYOUT,
	PARSER = Lookup.PARSER,
	TABPAGE = Lookup.TABPAGE,
	WINDOW = Lookup.WINDOW,
	RENDERER = Lookup.RENDERER,
	ELEMENT = Lookup.CREATE_ELEMENT,
	COMPONENT = Lookup.CREATE_COMPONENT,
	FRAGMENT = Lookup.CREATE_FRAGMENT,
}

return enum
