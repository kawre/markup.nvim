local markup = require("markup.core")

---@class markup.Inline.Anchor : markup.Inline
---@field protected super markup.Inline
local Anchor = markup.Inline:extend("markup.inline.anchor") ---@diagnostic disable-line: undefined-field

function Anchor:init(...)
	self:extend_default_props({
		style = { underline = true, fg = "#89b4fb" },
	})
	Anchor.super.init(self, ...)
end

---@type markup.Inline.constructor
return Anchor
