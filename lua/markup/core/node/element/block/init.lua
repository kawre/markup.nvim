local markup = require("markup")
local log = require("markup.logger") ---@diagnostic disable-line: unused-local

---@class markup.Block.props : markup.Inline.props

---@class markup.Block : markup.Inline
---@field protected super markup.Inline
local Block = markup.Inline:extend("markup.block") ---@diagnostic disable-line: undefined-field

---------------------------------
---- Constructor
---------------------------------

function Block:init(...)
	self:extend_default_props({
		display = "block",
	})
	Block.super.init(self, ...)
end

---------------------------------
---- Initializer
---------------------------------

---@class markup.Block.constructor.props : markup.Inline.constructor.props

---@alias markup.Block.constructor markup.Inline.constructor

---@type markup.Block.constructor
local MarkupBlock = Block ---@diagnostic disable-line: assign-type-mismatch

return MarkupBlock
