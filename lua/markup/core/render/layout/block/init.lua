local markup = require("markup.core")
local log = require("markup.logger") ---@diagnostic disable-line: unused-local

---@class markup.Render.Block : markup.Render.Layout
local RenderBlock = markup.Render.Layout:extend("RenderBlock")

function RenderBlock:occupy_full_width(line, constrains)
	line:append(markup.Pad(constrains.width - line:width()))
end

---@param constrains markup.Render.Layout.constrains
function RenderBlock:aggregate(constrains)
	local children = self.children

	local prev_child ---@type markup.Render.Layout
	for _, child in ipairs(children) do
		local is_block = child:is_block()
		if prev_child and (is_block or prev_child:is_block()) then
			self.builder:newl()
		end

		local lines, lines_len = child:computed_lines()
		for row = 1, lines_len do
			local line = lines[row]
			self:occupy_full_width(line, constrains)
			self.builder:line(self.builder.row + (row - 1)):append(line)
		end

		if is_block then
			self.builder:newl(lines_len - 1)
		end

		prev_child = child
	end
end

function RenderBlock:is_block()
	return true
end

return RenderBlock
