local markup = require("markup.core")

---@class markup.Underline : markup.Inline
---@field protected super markup.Inline
local Underline = markup.Inline:extend("markup.underline")

function Underline:init(...)
	self:extend_default_props({
		style = { underline = true },
	})
	Underline.super.init(self, ...)
end

---@alias markup.Underline.constructor
---| markup.Inline.constructor

---@type markup.Underline.constructor
return Underline
