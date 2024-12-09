local markup = require("markup.core")

---@class markup.Mark : markup.Inline
---@field protected super markup.Inline
local Mark = markup.Inline:extend("markup.mark")

function Mark:init(...)
	self:extend_default_props({
		style = { background = "yellow", color = "black" },
	})
	Mark.super.init(self, ...)
end

---@alias markup.Mark.constructor
---| markup.Inline.constructor

---@type markup.Mark.constructor
return Mark
