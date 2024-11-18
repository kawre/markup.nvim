local markup = require("markup")

---@class markup.Inline.Strong : markup.Inline
---@field protected super markup.Inline
local Strong = markup.Inline:extend("markup.inline.strong") ---@diagnostic disable-line: undefined-field

function Strong:init(...)
	self:_extend_default_props({
		style = { bold = true },
	})
	Strong.super.init(self, ...)
end

---@type markup.Inline.constructor
return Strong
