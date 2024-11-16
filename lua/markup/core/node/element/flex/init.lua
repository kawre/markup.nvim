local markup = require("markup")
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
	self:_extend_default_props({
		display = "flex",
	})
	Flex.super.init(self, ...)
end

---------------------------------
---- Methods
---------------------------------

function Flex:display_handler()
	local vertical = self.vertical

	if not vertical then
		for _, child in ipairs(self.children) do
			local maxs = self:max_size()
			local child_width = child:width()

			for row = 0, maxs.height - 1 do
				local line = child:_line(row)
				local padding = child_width - line:width()
				if padding > 0 then
					line:prepend(markup.Pad(padding, self))
				end
			end
		end
	end

	Flex.super.display_handler(self)

	local width = self:box_size()
	local align = self.align
	for _, line in pairs(self._.lines) do
		local padding = width - line:width()
		if align == "start" then
			line:append(markup.Pad(padding, self))
		elseif align == "center" then
			local halfpad = math.floor(padding / 2)
			local leftpad, rightpad = halfpad, halfpad + padding % 2
			line:prepend(markup.Pad(rightpad, self)):append(markup.Pad(leftpad, self))
		elseif align == "end" then
			line:prepend(markup.Pad(padding, self))
		end
	end
end

---------------------------------
---- Initializer
---------------------------------

---@class markup.Flex.constructor.props : markup.Block.constructor.props
---@alias markup.Flex.constructor markup.Block.constructor

---@type markup.Flex.constructor
local MarkupFlex = Flex ---@diagnostic disable-line: assign-type-mismatch

return MarkupFlex
