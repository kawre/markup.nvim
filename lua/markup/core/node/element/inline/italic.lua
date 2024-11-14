local markup = require("markup")

---@class markup.Inline.Italic : markup.Inline
---@field protected super markup.Inline
local Italic = markup.Element:extend("markup.inline.italic") ---@diagnostic disable-line: undefined-field

function Italic:init(...)
	self:_extend_default_props({
		style = { italic = true },
	})
	Italic.super.init(self, ...)
end

---@type markup.Inline.constructor
return Italic
