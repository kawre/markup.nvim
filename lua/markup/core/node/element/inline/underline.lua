local markup = require("markup")

---@class markup.Inline.Underline : markup.Inline
---@field protected super markup.Inline
local Underline = markup.Element:extend("markup.inline.underline") ---@diagnostic disable-line: undefined-field

function Underline:init(...)
	self:_extend_default_props({
		style = { underline = true },
	})
	Underline.super.init(self, ...)
end

---@type markup.Inline.constructor
return Underline
