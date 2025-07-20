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
	self.root:layout()
end

function RenderTree:paint()
	local mbox = self.root:margin_box_size()

	local lines = {}
	local fill = (" "):rep(mbox.width)
	for i = 1, mbox.height do
		lines[i] = fill
	end
	vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)

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

	if _Markup.debug_mode then
		box:debug_paint_margin(self.renderer, x, y)
		box:debug_paint_padding(self.renderer, x, y)
	end

	if type(props.style) == "string" or not vim.tbl_isempty(props.style) then
		box:paint(self.renderer, x, y)
	end

	-- if _Markup.debug_mode then
	-- end
end

return RenderTree
