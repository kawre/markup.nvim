local markup = require("markup")

---@class markup.Inline.Mark : markup.Inline
---@field protected super markup.Inline
local Mark = markup.Inline:extend("markup.inline.mark") ---@diagnostic disable-line: undefined-field

function Mark:init(...)
	self:extend_default_props({
		style = { background = "yellow", color = "black" },
	})
	Mark.super.init(self, ...)
end

---@type markup.Inline.constructor
return Mark
