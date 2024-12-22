local RenderLayout = require("markup.core.render.layout") ---@diagnostic disable-line: unused-local

---@class markup.Render.Flex.Item : markup.Render.Layout
local FlexItem = RenderLayout:extend("FlexItem")

function FlexItem:is_block_flow()
	return true
end

function FlexItem:aggregate()
	-- do nothing
end

function FlexItem:init(node)
	self.node = node
	self.children = { node }
	self.need_layout = true
end

return FlexItem
