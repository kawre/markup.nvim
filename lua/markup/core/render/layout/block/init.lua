local markup = require("markup.core")
local log = require("markup.logger") ---@diagnostic disable-line: unused-local

---@class markup.Render.Block : markup.Render.Layout
local RenderBlock = markup.Render.Layout:extend("RenderBlock")

---@param constrains markup.Render.Layout.constrains
function RenderBlock:aggregate(constrains)
	local children = self.children
	local intrinsic = self:intrinsic_size()

	local prev_child ---@type markup.Render.Layout
	for _, child in ipairs(children) do
		local is_block_flow = child:is_block_flow()
		if prev_child and (is_block_flow or prev_child:is_block_flow()) then
			self.builder:newl()
		end

		for _, line, is_last in child:computed_lines_iter() do
			local padding = intrinsic.width - line:width()
			if padding >= 1 then
				line:append(markup.Pad(padding))
			end
			self.builder:append(line):newl(is_last and 0 or 1)
		end

		prev_child = child
	end
end

function RenderBlock:is_block()
	return true
end

function RenderBlock:is_block_flow()
	return true
end

return RenderBlock
