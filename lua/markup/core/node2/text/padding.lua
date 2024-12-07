local markup = require("markup.core")

---@class markup.Padding : markup.Text
---@field protected super markup.Text
local Padding = markup.Text:extend("markup.padding") ---@diagnostic disable-line: undefined-field

local cache = {}

---@param n markup.Padding.constructor.props
function Padding:init(n, ...)
	if not cache[n] then
		cache[n] = (" "):rep(n)
	end
	Padding.super.init(self, cache[n], ...)
end

function Padding:_normalize_style()
	local style = Padding.super._normalize_style(self)
	if style and style.background then
		return style
	end
end

---@alias markup.Padding.constructor.props integer

---@alias markup.Padding.constructor fun(n: markup.Padding.constructor.props, parent?: markup.Node): markup.Padding

---@type markup.Padding.constructor
local MarkupPadding = Padding ---@diagnostic disable-line: assign-type-mismatch

return MarkupPadding
