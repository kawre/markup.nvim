local markup = require("markup.core")

---@class markup.Inline.Underline : markup.Inline
---@field protected super markup.Inline
local Underline = markup.Inline:extend("markup.inline.underline") ---@diagnostic disable-line: undefined-field

function Underline:init(...)
	self:extend_default_props({
		style = { underline = true },
	})
	Underline.super.init(self, ...)
end

---@type markup.Inline.constructor
return Underline
