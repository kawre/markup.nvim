local RenderLayout = require("markup.core.render.layout")

local log = require("markup.logger") ---@diagnostic disable-line: unused-local

---@class markup.Render.Inline : markup.Render.Layout
local RenderInline = RenderLayout:extend("RenderInline")

function RenderInline:height()
	return 1
end

function RenderInline:is_inline()
	return true
end

function RenderInline:layout()
	local children = self.children

	for _, child in ipairs(children) do
		assert(child:is_inline(), "Inline flow must contain only inline children")
		---@cast child markup.Render.Inline
		self.builder:line():append(child:computed_lines())
	end
end

return RenderInline
