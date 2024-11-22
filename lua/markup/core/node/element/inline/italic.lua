local markup = require("markup")

---@class markup.Inline.Italic : markup.Inline
---@field protected super markup.Inline
local Italic = markup.Inline:extend("markup.inline.italic") ---@diagnostic disable-line: undefined-field

function Italic:init(...)
	self:extend_default_props({
		style = { italic = true },
	})
	Italic.super.init(self, ...)
end

---@type markup.Inline.constructor
return Italic
