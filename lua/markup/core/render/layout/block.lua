local markup = require("markup.core")
local log = require("markup.logger") ---@diagnostic disable-line: unused-local

---@class markup.Render.Block : markup.Render.Layout
local RenderBlock = markup.Render.Layout:extend("RenderBlock")

function RenderBlock:is_block()
	return true
end

function RenderBlock:layout()
	local children = self.children
	local children_len = #children

	local prev_child ---@type markup.Render.Layout
	for _, child in ipairs(children) do
		if prev_child and (child:is_block() or prev_child:is_block()) then
			self.builder:newl()
		end

		local lines, lines_len = child:computed_lines()
		for row, line in pairs(lines) do
			self.builder:line(self.builder.row + row):append(line)
		end
		self.builder:newl(lines_len)

		prev_child = child
	end
end

return RenderBlock
