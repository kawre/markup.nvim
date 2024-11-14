local markup = require("markup")

---@class markup.Padding : markup.Text
---@field protected super markup.Text
local Padding = markup.Text:extend("MarkupPadding") ---@diagnostic disable-line: undefined-field

local cache = {}

---@param n markup.Padding.constructor.props
function Padding:init(n, ...)
	if not cache[n] then
		cache[n] = (" "):rep(n)
	end

	Padding.super.init(self, cache[n], ...)
end

---@alias markup.Padding.constructor.props integer

---@alias markup.Padding.constructor fun(n: markup.Padding.constructor.props, parent?: markup.Node): markup.Padding

---@type markup.Padding.constructor
local MarkupPadding = Padding ---@diagnostic disable-line: assign-type-mismatch

return MarkupPadding
