local markup = require("markup.core")
local log = require("markup.logger") ---@diagnostic disable-line: unused-local

---@class markup.Inline.props : markup.Element.props

---@class markup.Inline : markup.Element
---@field protected _ markup.Inline.props
local Inline = markup.Element:extend("markup.inline") ---@diagnostic disable-line: undefined-field

function Inline:_flex_merge_handler()
	local nodes, vertical = self.child_nodes, self.vertical
	local spacing = self.spacing

	for i, child in ipairs(nodes) do
		local not_last = i ~= #nodes

		local prev_sibling = child:prev_sibling()
		if prev_sibling and (prev_sibling:is_br() or child:is_br()) then
			self.builder:newl()
		end

		if child:is_type("text") then
			---@cast child markup.Text
			self.builder:append(child):append(markup.Pad(spacing, self))

			if not vertical then
				local maxs = self:max_size()
				local pad = child:width() + spacing
				for row = 1, maxs.height - 1 do
					self.builder:line(row):append(markup.Pad(pad, self))
				end
			else
				self.builder:newl(not_last and spacing or 0)
			end
		else
			---@cast child markup.Element
			local lines = child:computed_lines()

			local maxs = self:max_size()
			if not vertical then
				local width = child:width()

				for row = 0, maxs.height - 1 do
					local line = child.builder:line(row)
					local padding = width - line:width()
					if padding > 0 then
						line:append(markup.Pad(padding, child))
					end
					if spacing > 0 and not_last then
						line:append(markup.Pad(spacing, self))
					end

					self.builder:append(line, self.builder.row + row)
				end

				self.builder.row = 0
			else
				for row, line in pairs(lines) do
					self.builder:append(line, self.builder.row + row)
				end

				self.builder:newl(#lines + (not_last and spacing or 0))
			end
		end
	end
end

function Inline:_merge_handler()
	local nodes = self.child_nodes

	for _, child in ipairs(nodes) do
		local prev_sibling = child:prev_sibling()
		if prev_sibling and (prev_sibling:is_br() or child:is_br()) then
			self.builder:newl()
		end

		if child:is_type("text") then
			---@cast child markup.Text
			self.builder:append(child)
		else
			---@cast child markup.Element
			local lines = child:computed_lines()
			for row, line in pairs(lines) do
				self.builder:append(line, self.builder.row + row)
			end
			self.builder:newl(#lines)
		end
	end
end

function Inline:display_handler()
	self:_merge_handler()
	-- self:_apply_border()
	self:_apply_spacing()
end

function Inline:_align_handler()
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

---@class markup.Inline.constructor.props : markup.Element.constructor.props

---@alias markup.Inline.constructor markup.Element.constructor

---@type markup.Inline.constructor
local MarkupInline = Inline ---@diagnostic disable-line: assign-type-mismatch

return MarkupInline
