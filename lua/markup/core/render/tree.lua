local RenderNodeFactory = require("markup.core.factory.render-box")
local log = require("markup.logger") ---@diagnostic disable-line: unused-local

---@class markup.Render.Tree
local RenderTree = {}
RenderTree.__index = RenderTree

---@param renderer markup.Renderer
function RenderTree:new(renderer)
	self = setmetatable({}, RenderTree)

	self.renderer = renderer
	self.root = RenderNodeFactory.create_root(renderer)

	return self
end

function RenderTree:build()
	self.root:build()
end

function RenderTree:layout()
	-- self.root:layout()
	for _, child in ipairs(self.root.children) do
		child:layout()
	end
end

function RenderTree:paint()
	local mbox = self.root:margin_box_size()

	local lines = {}
	local fill = (" "):rep(1000)
	for i = 1, math.max(mbox.height, 1000) do
		lines[i] = fill
	end
	vim.api.nvim_buf_set_lines(self.renderer.bufnr, 0, -1, false, lines)

	self:traverse_and_paint(0, 0, self.root)
end

---(x, y) are the coordinates of the parent margin box
---@param x integer
---@param y integer
---@param box markup.Render.Box
function RenderTree:traverse_and_paint(x, y, box)
	if box:is("text") then
		box:paint(self.renderer, x, y)
		return
	end

	local props = box.props
	local cx = x + props.margin_left + props.padding_left
	local cy = y + props.margin_top + props.padding_top
	for _, child in box:iter_children() do
		self:traverse_and_paint(cx + child.ox, cy + child.oy, child)
	end

	if props.style.bg then
		box:paint(self.renderer, x, y)
	end
end

return RenderTree
