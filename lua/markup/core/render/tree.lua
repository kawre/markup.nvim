local markup = require("markup.core")

local log = require("markup.logger") ---@diagnostic disable-line: unused-local

---@class markup.Render.Tree : markup.Render.Layout
local RenderTree = markup.Object("markup.render.tree")

---@class markup.Render.Tree.static
RenderTree.static = RenderTree.static

---@param root markup.Renderer.Root
function RenderTree:init(root)
	self.view = markup.Render.View(root)
end

return RenderTree
