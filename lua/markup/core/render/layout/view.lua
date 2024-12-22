local markup = require("markup.core")
local log = require("markup.logger") ---@diagnostic disable-line: unused-local

---@class markup.Render.View : markup.Render.Block
---@field protected super markup.Render.Block
local RenderView = markup.Render.Block:extend("RenderView")

---@param root markup.Renderer.Root
function RenderView:init(root)
	RenderView.super.init(self, root.current.state_node)

	self.frame = root.owner
end

function RenderView:layout()
	RenderView.super.layout(self, self.node.props.style)
end

function RenderView:box_width()
	return self.frame.win:get_width()
end

function RenderView:box_height()
	return self.frame.win:get_height()
end

function RenderView:box_size()
	return { width = self:box_width(), height = self:box_height() }
end

return RenderView
