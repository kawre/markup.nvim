local markup = require("markup.core")

---@class markup.Strong : markup.Inline
---@field protected super markup.Inline
local Strong = markup.Inline:extend("markup.strong")

function Strong:init(...)
	self:extend_default_props({
		style = { bold = true },
	})
	Strong.super.init(self, ...)
end

---@alias markup.Strong.constructor
---| markup.Inline.constructor

---@type markup.Strong.constructor
return Strong
