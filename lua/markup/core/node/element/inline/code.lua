local markup = require("markup")

---@class markup.Inline.Code : markup.Inline
---@field protected super markup.Inline
local Code = markup.Inline:extend("markup.inline.code") ---@diagnostic disable-line: undefined-field

function Code:init(...)
	self:extend_default_props({
		style = { link = "MarkupCode" },
	})
	Code.super.init(self, ...)
end

---@type markup.Inline.constructor
return Code
