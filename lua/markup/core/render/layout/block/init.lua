local markup = require("markup.core")
local log = require("markup.logger") ---@diagnostic disable-line: unused-local

---@class markup.Render.Block : markup.Render.Layout
local RenderBlock = markup.Render.Layout:extend("RenderBlock")

---@param constrains markup.Render.Layout.constrains
function RenderBlock:aggregate(constrains)
	local children = self.children
	local box = self:box_size()

	local prev_child ---@type markup.Render.Layout
	for _, child in ipairs(children) do
		local is_block_flow = child:is_block_flow()
		if prev_child and (is_block_flow or prev_child:is_block_flow()) then
			self.builder:newl()
		end

		local lines, lines_len = child:computed_lines()
		for row, line in ipairs(lines) do
			line:append(markup.Pad(box.width - line:width()))
			self.builder:line(self.builder.row + (row - 1)):append(line)
		end

		if is_block_flow then
			self.builder:newl(lines_len - 1)
		end

		prev_child = child
	end
	log.info(self.builder.lines)
end

function RenderBlock:is_block()
	return true
end

function RenderBlock:is_block_flow()
	return true
end

return RenderBlock
