local markup = require("markup.core")
local log = require("markup.logger") ---@diagnostic disable-line: unused-local
local RenderBlock = require("markup.core.render.layout.block")

---@class markup.Render.Flex : markup.Render.Layout
local RenderFlex = RenderBlock:extend("RenderFlex")

function RenderFlex:is_flex()
	return true
end

function RenderFlex:justify()
	-- TODO
end

---@param constrains markup.Render.Layout.constrains
function RenderFlex:align(constrains)
	local align = self.node.props.align
	local width = constrains and constrains.width or self:box_size().width

	for _, line in pairs(self:computed_lines()) do
		local padding = width - line:width()
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
	local intrinsic = self:intrinsic_size()

	for i, child in ipairs(children) do
		local not_last = i ~= children_len

		if props.horizontal then
			local width = child.builder:width()

			for row = 1, intrinsic.height do
				local line = child.builder:line(row)

				local padding = width - line:width()
				if padding > 0 then
					line:append(markup.Pad(padding))
				end
				if props.spacing > 0 and not_last then
					line:append(markup.Pad(props.spacing))
				end

				self.builder:append(line):newl()
			end

			self.builder.row = 1
		else
			for _, line, is_last in child:computed_lines_iter() do
				self.builder:append(line):newl(is_last and 0)
			end

			if not_last then
				self.builder:newl(1 + (props.spacing or 0))
			end
		end
	end
end

function RenderFlex:layout(style)
	RenderFlex.super.layout(self, style)

	self:align()
	self:justify()
end

return RenderFlex
