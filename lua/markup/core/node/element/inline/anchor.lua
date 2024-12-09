local markup = require("markup.core")

---@class markup.Anchor : markup.Inline
---@field protected super markup.Inline
local Anchor = markup.Inline:extend("markup.anchor")

function Anchor:init(...)
	self:extend_default_props({
		style = { underline = true, fg = "#89b4fb" },
	})
	Anchor.super.init(self, ...)
end

---@alias markup.Anchor.constructor
---| markup.Inline.constructor

---@type markup.Anchor.constructor
return Anchor
