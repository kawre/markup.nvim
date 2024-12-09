local markup = require("markup.core")

---@class markup.Code : markup.Inline
---@field protected super markup.Inline
local Code = markup.Inline:extend("markup.code")

function Code:init(...)
	self:extend_default_props({
		style = { link = "MarkupCode" },
	})
	Code.super.init(self, ...)
end

---@alias markup.Code.constructor
---| markup.Inline.constructor

---@type markup.Code.constructor
return Code
