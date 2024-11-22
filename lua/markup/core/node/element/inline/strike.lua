local markup = require("markup")

---@class markup.Inline.Strike : markup.Inline
---@field protected super markup.Inline
local Strike = markup.Inline:extend("markup.inline.strike") ---@diagnostic disable-line: undefined-field

function Strike:init(...)
	self:extend_default_props({
		style = { strikethrough = true },
	})
	Strike.super.init(self, ...)
end

---@type markup.Inline.constructor
return Strike
