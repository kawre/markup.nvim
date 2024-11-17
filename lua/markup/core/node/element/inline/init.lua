local markup = require("markup")
local log = require("markup.logger") ---@diagnostic disable-line: unused-local

---@class markup.Inline.props : markup.Element.props

---@class markup.Inline : markup.Element
---@field protected _ markup.Inline.props
local Inline = markup.Element:extend("markup.inline") ---@diagnostic disable-line: undefined-field

function Inline:display_handler()
	local spacing, children, vertical = self.spacing, self.child_nodes, self.vertical
	local is_hor = self:is_box() and not vertical

	for i, child in ipairs(children) do
		local is_not_last = i ~= #children

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
				if spacing > 0 and is_hor and is_not_last then
					line:append(markup.Pad(spacing, self))
				end
				self:_append(line, self:_row() + row)
			end

			if is_hor then
				self:_set_row(0)
			else
				self:_newl(#lines + (is_not_last and spacing or 0))
			end
		end
	end

	self:_apply_periferals()
	self:_apply_spacing()
end

---@class markup.Inline.constructor.props : markup.Element.constructor.props

---@alias markup.Inline.constructor markup.Element.constructor

---@type markup.Inline.constructor
local MarkupInline = Inline ---@diagnostic disable-line: assign-type-mismatch

return MarkupInline
