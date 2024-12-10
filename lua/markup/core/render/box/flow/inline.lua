local markup = require("markup.core")

---@class markup.Render.Inline : markup.Render.Flow
local RenderInline = markup.Render.Flow:extend("markup.render.inline")

function RenderInline:layout()
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

return RenderInline
