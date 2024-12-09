local markup = require("markup.core")

---@class markup.Sup : markup.Inline
---@field protected super markup.Inline
local Sup = markup.Inline:extend("markup.sup")

function Sup:init(...)
	self:extend_default_props({
		style = { color = "#9399b3" },
	})
	Sup.super.init(self, ...)
end

---@alias markup.Sup.constructor
---| markup.Inline.constructor

---@type markup.Sup.constructor
return Sup
