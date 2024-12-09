local markup = require("markup.core")

---@class markup.Grid : markup.Block
---@field protected super markup.Block
local Grid = markup.Block:extend("markup.grid")

function Grid:init(...)
	self:extend_default_props({
		display = "grid",
	})
	Grid.super.init(self, ...)
end

---@alias markup.Grid.constructor
---| markup.Block.constructor

---@type markup.Grid.constructor
return Grid
