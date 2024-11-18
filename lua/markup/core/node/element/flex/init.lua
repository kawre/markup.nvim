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

function Flex:_merge_handler()
	local nodes, vertical = self.child_nodes, self.vertical

	local spacing = self.spacing

	for i, child in ipairs(nodes) do
		local not_last = i ~= #nodes

		local prev_sibling = child.prev_sibling
		if prev_sibling and (prev_sibling:is_br() or child:is_br()) then
			self:_newl()
		end

		if child:is_type("text") then
			---@cast child markup.Text
			self:_append(child):_append(markup.Pad(spacing, self))

			if not vertical then
				local maxs = self:max_size()
				local pad = child:width() + spacing
				for row = 1, maxs.height - 1 do
					self:_line(row):append(markup.Pad(pad, self))
				end
			else
				self:_newl(not_last and spacing or 0)
			end
		else
			---@cast child markup.Element
			local lines = child:computed_lines()

			if not vertical then
				local maxs = self:max_size()
				local width = child:width()

				for row = 0, maxs.height - 1 do
					local line = child:_line(row)
					local padding = width - line:width()
					if padding > 0 then
						line:append(markup.Pad(padding, child))
					end
					if spacing > 0 and not_last then
						line:append(markup.Pad(spacing, self))
					end

					self:_append(line, self:_row() + row)
				end

				self:_set_row(0)
			else
				for row, line in pairs(lines) do
					self:_append(line, self:_row() + row)
				end

				self:_newl(#lines + (not_last and spacing or 0))
			end
		end
	end
end

function Flex:display_handler()
	Flex.super.display_handler(self)
	self:_align_handler()
end

function Flex:_align_handler()
	local width = self:box_size()
	local align = self.align
	for _, line in pairs(self:computed_lines()) do
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
