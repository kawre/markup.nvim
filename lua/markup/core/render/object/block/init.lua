local markup = require("markup.core")

---@class markup.Render.Block : markup.Render.Object
local RenderBlock = markup.Render.Object:extend("markup.render.block")

function RenderBlock:layout()
	local children = self.children

	for _, child in ipairs(children) do
		---@cast child markup.Render.Block
		assert(child:is_block_flow(), "Block flow must contain only block children")

		for _, line in pairs(child:computed_lines()) do
			self.builder:append(line):newl()
		end
	end
end

return RenderBlock
