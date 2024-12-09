local markup = require("markup.core")

---@class markup.Inline : markup.Element
---@field protected super markup.Element
local Inline = markup.Element:extend("markup.inline")

function Inline:init(...)
	self:extend_default_props({
		display = "inline",
	})
	Inline.super.init(self, ...)
end

---@alias markup.Inline.constructor
---| markup.Element.constructor

---@type markup.Inline.constructor
return Inline
