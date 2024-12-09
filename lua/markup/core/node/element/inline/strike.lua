local markup = require("markup.core")

---@class markup.Strike : markup.Inline
---@field protected super markup.Inline
local Strike = markup.Inline:extend("markup.strike")

function Strike:init(...)
	self:extend_default_props({
		style = { strikethrough = true },
	})
	Strike.super.init(self, ...)
end

---@alias markup.Strike.constructor
---| markup.Inline.constructor

---@type markup.Strike.constructor
return Strike
