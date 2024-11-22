local markup = require("markup")

---@class markup.Grid : markup.Block
---@field protected super markup.Block
local Grid = markup.Block:extend("markup.grid") ---@diagnostic disable-line: undefined-field

---------------------------------
---- Constructor
---------------------------------

function Grid:init(...)
	self:extend_default_props({
		display = "grid",
	})
	Grid.super.init(self, ...)
end

---------------------------------
---- Methods
---------------------------------

function Grid:after_render()
	error("Grid not yet implemented")
end

---------------------------------
---- Initializer
---------------------------------

---@class markup.Grid.constructor.props : markup.Block.constructor.props
---@alias markup.Grid.constructor markup.Block.constructor

---@type markup.Grid.constructor
return Grid
