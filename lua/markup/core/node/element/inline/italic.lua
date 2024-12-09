local markup = require("markup.core")

---@class markup.Italic : markup.Inline
---@field protected super markup.Inline
local Italic = markup.Inline:extend("markup.italic")

function Italic:init(...)
	self:extend_default_props({
		style = { italic = true },
	})
	Italic.super.init(self, ...)
end

---@alias markup.Italic.constructor
---| markup.Inline.constructor

---@type markup.Italic.constructor
return Italic
