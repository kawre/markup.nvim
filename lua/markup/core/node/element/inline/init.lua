local markup = require("markup")
local log = require("markup.logger") ---@diagnostic disable-line: unused-local

---@class markup.Inline.props : markup.Element.props

---@class markup.Inline : markup.Element
---@field protected _ markup.Inline.props
local Inline = markup.Element:extend("markup.inline") ---@diagnostic disable-line: undefined-field

function Inline:_merge_handler()
	local nodes = self.child_nodes

	for _, child in ipairs(nodes) do
		local prev_sibling = child.prev_sibling
		if prev_sibling and (prev_sibling:is_br() or child:is_br()) then
			self:_newl()
		end

		if child:is_type("text") then
			---@cast child markup.Text
			self:_append(child)
		else
			---@cast child markup.Element
			local lines = child:computed_lines()
			for row, line in pairs(lines) do
				self:_append(line, self:_row() + row)
			end
			self:_newl(#lines)
		end
	end
end

function Inline:display_handler()
	self:_merge_handler()
	self:_apply_peripherals()
	self:_apply_spacing()
end

---@class markup.Inline.constructor.props : markup.Element.constructor.props

---@alias markup.Inline.constructor markup.Element.constructor

---@type markup.Inline.constructor
local MarkupInline = Inline ---@diagnostic disable-line: assign-type-mismatch

return MarkupInline
