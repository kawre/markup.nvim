local markup = require("markup.core")

local log = require("markup.logger") ---@diagnostic disable-line: unused-local

---@class markup.Render.Inline : markup.Render.Object
local RenderInline = markup.Render.Object:extend("RenderInline")

function RenderInline:height()
	return 1
end

function RenderInline:computed_line()
	return self.builder:line(0)
end

function RenderInline:layout()
	local children = self.children

	for _, child in ipairs(children) do
		---@cast child markup.Render.Inline
		self.builder:append(child:computed_line())
	end
end

return RenderInline
