local markup = require("markup.core")

---@class markup.Render.Flow : markup.Render.Box
---@field protected super markup.Render.Box
local RenderFlow = markup.Render.Box:extend("markup.render.flow")

function RenderFlow:init(node)
	self.node = node
	self.builder = markup.RendererBuilder()
end

function RenderFlow:is_inline()
	--
end

function RenderFlow:is_inline_flow()
	--
end

function RenderFlow:is_block_flow()
	--
end

function RenderFlow:box_width()
	return self.builder:width()
end

function RenderFlow:box_height()
	return self.builder:height()
end

-- Size of the box excluding padding, border, margin
function RenderFlow:box_size()
	return self:box_width(), self:box_height()
end

function RenderFlow:layout()
	error("Must be implemented by a subclass")
end

return RenderFlow
