local markup = require("markup.core")

local log = require("markup.logger") ---@diagnostic disable-line: unused-local
local NodeType = require("markup.core.node.enum").Type

---@class markup.Element.props : markup.Node.props
---@field style markup.Element.style
---@field display markup.Element.display
---@field padding markup.Element.padding
---@field margin markup.Element.margin
---@field align markup.Box.align
---@field spacing markup.Box.spacing
---@field vertical boolean
---@field reverse boolean
---@field on_submit? fun()
---@field on_key? table<string, fun()>
---@field border? markup.Element.border

---@class markup.Element : markup.Node
---@field protected super markup.Node
---@field private _pending_props markup.Element.constructor.props
---@field props markup.Element.props
---@field static markup.Element.static
---@field child_nodes markup.Node[]
---@field builder markup.Renderer.Builder
local Element = markup.Node:extend("markup.element")
Element.__type = "element"

---@class markup.Element.static : markup.Node.static
Element.static = Element.static

---@return markup.Element.props
Element.static.get_default_props = function()
	return {
		style = {},
		display = "inline",
		padding = 0,
		margin = 0,
		align = "start",
		spacing = 0,
		vertical = true,
		reverse = false,
		size = {},
	}
end

---@param props? markup.Element.constructor.props
---@param style? markup.Element.style.props
function Element:init(props, style)
	props = self:normalize_props(props, style)
	Element.super.init(self, NodeType.ELEMENT, props)

	self._pending_props = nil
	self.style = nil
end

function Element:apply_spacing()
	if not self:_non_zero_spacing() then
		return
	end

	local lines = self:computed_lines()
	local width = self:width()
	local mar, pad = self.margin, self.padding

	-- Apply vertical spacing
	if self:is_block_kind() then
		for _ = 1, self.padding.top do
			self:_insert_line(0, markup.Pad(width, self))
		end
		for _ = 1, self.margin.top do
			self:_insert_line(0, markup.Pad(width, self.parent))
		end
		for _ = 1, self.padding.bottom do
			self:_insert_line(nil, markup.Pad(width, self))
		end
		for _ = 1, self.margin.bottom do
			self:_insert_line(nil, markup.Pad(width, self.parent))
		end
	end

	-- Apply horizontal spacing
	for row, line in pairs(lines) do
		if row < mar.bottom or row > #lines - mar.top then
			line:prepend(markup.Pad(mar.left + pad.left, self.parent))
			line:append(markup.Pad(mar.right + pad.right, self.parent))
		else
			line:prepend(markup.Pad(pad.left, self))
			line:prepend(markup.Pad(mar.left, self.parent))
			line:append(markup.Pad(pad.right, self))
			line:append(markup.Pad(mar.right, self.parent))
		end
	end
end

---@param element markup.Element
function Element:inherit_style(element)
	if not element then
		return self.props.style
	else
		return vim.tbl_deep_extend("force", element.style, self.props.style)
	end
end

---@param parent markup.Element
function Element:inherit_display(parent)
	if parent and parent:is_box() then
		return parent.vertical and "block" or "inline-block"
	else
		return self.props.display
	end
end

function Element:children()
	return vim.tbl_filter(function(child)
		---@cast child markup.Element
		return child:is_type(NodeType.ELEMENT)
	end, self.child_nodes)
end

---@return integer
function Element:width()
	if self.props.size.width then
		return self.props.size.width
	end

	return self.builder:width()
end

---@return integer
function Element:height()
	if self.props.size.height then
		return self.props.size.height
	end

	return self.builder:height()
end

---@return integer, integer
function Element:size()
	return self:width(), self:height()
end

---@return integer, integer
function Element:box_size()
	if self:is_br() and not self:is_box_item() then
		return self.owner:win_get_width(), self.owner:win_get_height()
	else
		return self:size()
	end
end

function Element:max_size()
	local max_width, max_height = 0, 0
	for _, child in ipairs(self:children()) do
		max_height = math.max(max_height, child:height())
		max_width = math.max(max_width, child:width())
	end

	return { width = max_width, height = max_height }
end

function Element.static.normalize_style(style)
	if type(style) == "string" then
		return { link = style }
	else
		return style
	end
end

function Element.static.normalize_spacing(spacing)
	local t = spacing

	if type(t) == "number" then
		return { top = t, right = t, bottom = t, left = t }
	elseif vim.islist(t) then
		if #t == 1 then
			return { top = t[1], right = t[1], bottom = t[1], left = t[1] }
		elseif #t == 2 then
			return { top = t[1], right = t[2], bottom = t[1], left = t[2] }
		elseif #t == 3 then
			return { top = t[1], right = t[2], bottom = t[3], left = t[2] }
		elseif #t == 4 then
			return { top = t[1], right = t[2], bottom = t[3], left = t[4] }
		end
	else
		return { top = t.top or 0, right = t.right or 0, bottom = t.bottom or 0, left = t.left or 0 }
	end
end

---@param props? markup.Element.constructor.props
function Element:extend_default_props(props)
	self._pending_props = vim.tbl_deep_extend("force", props or {}, self._pending_props or {})
end

---@param props any
function Element:normalize_props(props, style)
	local default_props = Element.static.get_default_props()
	local pending_props = self._pending_props or {}
	props = vim.tbl_deep_extend("keep", props or {}, pending_props, default_props)

	if style then
		style = Element.static.normalize_style(style)
		props.style = vim.tbl_deep_extend("keep", style, props.style)
	end
	if props.style then
		props.style = Element.static.normalize_style(props.style)
	end

	return props
end

---@class markup.Element.constructor.props
---@field style? markup.Element.style.props element style
---@field display? markup.Element.display element display
---@field margin? markup.Element.margin element margin
---@field padding? markup.Element.padding element padding
---@field align? markup.Box.align box align
---@field spacing? markup.Box.spacing box spacing
---@field vertical? boolean box vertical
---@field reverse? boolean box reverse

---@alias markup.Element.style.props
---| markup.Element.style
---| string

---@alias markup.Element.constructor
---| fun(props?: markup.Element.constructor.props, style?: markup.Element.style.props): markup.Element
---| { static: markup.Element.static }
---| markup.Element.static

---@type markup.Element.constructor
return Element
