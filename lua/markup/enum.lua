local log = require("markup.logger") ---@diagnostic disable-line: unused-local
local Lookup = require("markup.core.enum").Lookup
local Enum = require("markup.core.create.enum")

---@class markup.enum : markup.Enum
local enum = Enum()

enum.Node = {
	BLOCK = Lookup.BLOCK,
	LIST = Lookup.LIST,
	LISTITEM = Lookup.LISTITEM,
	OLIST = Lookup.OLIST,
	FLEX = Lookup.FLEX,
	HFLEX = Lookup.HFLEX,
	BOX = Lookup.BOX,
	GRID = Lookup.GRID,
	INLINE = Lookup.INLINE,
	ANCHOR = Lookup.ANCHOR,
	CODE = Lookup.CODE,
	ITALIC = Lookup.ITALIC,
	MARK = Lookup.MARK,
	STRIKE = Lookup.STRIKE,
	STRONG = Lookup.STRONG,
	SUB = Lookup.SUB,
	SUP = Lookup.SUP,
	UNDERLINE = Lookup.UNDERLINE,
	TEXT = Lookup.TEXT,
	PAD = Lookup.PAD,
}

enum.CreateNode = enum:map(enum.Node, function(_, v)
	local core = require("markup.core")
	return function(props)
		return core.create_element(require(v), props)
	end
end)

enum.Lookup = {
	enum.CreateNode,
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
