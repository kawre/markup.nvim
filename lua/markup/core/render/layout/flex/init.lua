local markup = require("markup.core")
local log = require("markup.logger") ---@diagnostic disable-line: unused-local
local RenderTree = require("markup.core.render.tree")
local RenderBlock = require("markup.core.render.layout.block")

---@class markup.Render.Flex : markup.Render.Layout
local RenderFlex = RenderBlock:extend("RenderFlex")

function RenderFlex:is_flex()
	return true
end

---@param constrains markup.Render.Layout.constrains
function RenderFlex:align(constrains)
	local align = self.node.props.align

	for _, line in pairs(self:computed_lines()) do
		local padding = constrains.width - line:width()
		if align == "start" then
			line:append(markup.Pad(padding))
		elseif align == "center" then
			local halfpad = math.floor(padding / 2)
			local leftpad, rightpad = halfpad, halfpad + padding % 2
			line:prepend(markup.Pad(rightpad)):append(markup.Pad(leftpad))
		elseif align == "end" then
			line:prepend(markup.Pad(padding))
		end
	end
end

---@param constrains markup.Render.Layout.constrains
function RenderFlex:aggregate(constrains)
	local children = self.children
	local props = self.node.props

	local children_len = #children
	local pre = self:content_size()

	for i, child in ipairs(children) do
		local not_last = i ~= children_len

		if props.horizontal then
			local width = child.builder:width()

			for row = 1, pre.height do
				local line = child.builder:line(row)

				local padding = width - line:width()
				if padding > 0 then
					line:append(markup.Pad(padding))
				end
				if props.spacing > 0 and not_last then
					line:append(markup.Pad(props.spacing))
				end

				self.builder:line(self.builder.row + (row - 1)):append(line)
			end

			self.builder.row = 1
		else
			if i ~= 1 then
				self.builder:newl()
			end

			local lines, lines_len = child:computed_lines()

			for row, line in ipairs(lines) do
				self.builder:line(self.builder.row + (row - 1)):append(line)
			end

			-- TODO temporary fix for newl
			if not_last then
				self.builder:newl(lines_len - 1 + (not_last and props.spacing or 0))
			end
		end
	end

	self:align(constrains)
end

function RenderFlex:layout(constrains)
	RenderFlex.super.layout(self, constrains)
end

return RenderFlex
