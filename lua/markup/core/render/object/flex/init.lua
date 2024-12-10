local markup = require("markup.core")

---@class markup.Render.Flex : markup.Render.Object
local RenderFlex = markup.Render.Object:extend("markup.render.flex")

function RenderFlex:layout()
	-- local nodes, vertical = self.child_nodes, self.vertical
	-- local spacing = self.spacing
	--
	-- for i, child in ipairs(nodes) do
	-- 	local not_last = i ~= #nodes
	--
	-- 	local prev_sibling = child:prev_sibling()
	-- 	if prev_sibling and (prev_sibling:is_br() or child:is_br()) then
	-- 		self.builder:newl()
	-- 	end
	--
	-- 	if child:is_type("text") then
	-- 		---@cast child markup.Text
	-- 		self.builder:append(child):append(markup.Pad(spacing, self))
	--
	-- 		if not vertical then
	-- 			local maxs = self:max_size()
	-- 			local pad = child:width() + spacing
	-- 			for row = 1, maxs.height - 1 do
	-- 				self.builder:line(row):append(markup.Pad(pad, self))
	-- 			end
	-- 		else
	-- 			self.builder:newl(not_last and spacing or 0)
	-- 		end
	-- 	else
	-- 		---@cast child markup.Element
	-- 		local lines = child:computed_lines()
	--
	-- 		local maxs = self:max_size()
	-- 		if not vertical then
	-- 			local width = child:width()
	--
	-- 			for row = 0, maxs.height - 1 do
	-- 				local line = child.builder:line(row)
	-- 				local padding = width - line:width()
	-- 				if padding > 0 then
	-- 					line:append(markup.Pad(padding, child))
	-- 				end
	-- 				if spacing > 0 and not_last then
	-- 					line:append(markup.Pad(spacing, self))
	-- 				end
	--
	-- 				self.builder:append(line, self.builder.row + row)
	-- 			end
	--
	-- 			self.builder.row = 0
	-- 		else
	-- 			for row, line in pairs(lines) do
	-- 				self.builder:append(line, self.builder.row + row)
	-- 			end
	--
	-- 			self.builder:newl(#lines + (not_last and spacing or 0))
	-- 		end
	-- 	end
	-- end
end

return RenderFlex
