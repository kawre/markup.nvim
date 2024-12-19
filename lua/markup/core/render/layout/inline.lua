local RenderObject = require("markup.core.render.layout")

local log = require("markup.logger") ---@diagnostic disable-line: unused-local

---@class markup.Render.Inline : markup.Render.Layout
local RenderInline = RenderObject:extend("RenderInline")

function RenderInline:height()
	return 1
end

function RenderInline:computed_line()
	return self.builder:line(0)
end

function RenderInline:layout()
	local children = self.children

	for _, child in ipairs(children) do
		-- assert(child:is_inline_flow(), "Inline flow must contain only inline children")
		---@cast child markup.Render.Inline
		self.builder:append(child:computed_line())
	end
end

return RenderInline
