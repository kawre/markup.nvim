local markup = require("markup.core")
local u = require("markup.utils") ---@diagnostic disable-line: unused-local
local log = require("markup.logger") ---@diagnostic disable-line: unused-local

---@class markup.Flex.props : markup.Block.props

---@class markup.Flex : markup.Block
---@field protected _ markup.Flex.props
---@field protected super markup.Block
local Flex = markup.Block:extend("markup.flex") ---@diagnostic disable-line: undefined-field

---------------------------------
---- Constructor
---------------------------------

function Flex:init(...)
	self:extend_default_props({
		display = "flex",
	})
	Flex.super.init(self, ...)
end

---------------------------------
---- Methods
---------------------------------

function Flex:display_handler()
	self:_flex_merge_handler()
	self:_apply_border()
	self:_apply_spacing()
	self:_align_handler()
end

---------------------------------
---- Initializer
---------------------------------

---@class markup.Flex.constructor.props : markup.Block.constructor.props
---@alias markup.Flex.constructor markup.Block.constructor

---@type markup.Flex.constructor
local MarkupFlex = Flex ---@diagnostic disable-line: assign-type-mismatch

return MarkupFlex
