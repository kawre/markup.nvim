local markup = require("markup.core")

---@class markup.Sub : markup.Inline
---@field protected super markup.Inline
local Sub = markup.Inline:extend("markup.sub")

function Sub:init(...)
	self:extend_default_props({
		style = { color = "#9399b3" },
	})
	Sub.super.init(self, ...)
end

---@alias markup.Sub.constructor
---| markup.Inline.constructor

---@type markup.Sub.constructor
return Sub
