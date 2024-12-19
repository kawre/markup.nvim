local markup = require("markup.core")
local log = require("markup.logger") ---@diagnostic disable-line: unused-local
local RenderBlock = require("markup.core.render.layout.block")

---@class markup.Render.Flex : markup.Render.Layout
local RenderFlex = RenderBlock:extend("RenderFlex")

function RenderFlex:layout()
	local children = self.children
	local props = self.node.props

	local children_len = #children
	local prev_child ---@type markup.Render.Layout

	log.info(props.vertical)
	for i, child in ipairs(children) do
		local not_last = i ~= children_len

		if prev_child and (child:is_block() or prev_child:is_block()) then
			self.builder:newl()
		end

		local box = child:box_size()

		if not props.vertical then
			local width = box.width

			for row = 0, box.height - 1 do
				local line = child.builder:line(row)
				local padding = width - line:width()
				if padding > 0 then
					line:append(markup.Pad(padding))
				end
				if props.spacing > 0 and not_last then
					line:append(markup.Pad(props.spacing))
				end

				self.builder:append(line, self.builder.row + row)
			end

			self.builder.row = 0
		else
			local lines = child:computed_lines()
			local lines_len = #lines

			for row, line in pairs(lines) do
				self.builder:append(line, self.builder.row + row)
			end
			self.builder:newl(lines_len + (not_last and props.spacing or 0))
		end

		prev_child = child
	end
end

return RenderFlex
