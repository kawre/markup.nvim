local markup = require("markup")
local log = require("markup.logger") ---@diagnostic disable-line: unused-local
local RenderTree = require("markup.core.render.tree")
local RendererFactory = require("markup.core.factory.renderer")
local Reconciler = require("markup.core.reconciler")
local Window = require("markup.core.window.init2")

---@class markup.Renderer.meta.render
---@field node_root markup.Node
---@field fiber_root markup.Fiber
---@field render_root markup.Render.Box
---@field index integer

---@class markup.Renderer.meta
---@field render_count integer
---@field renders markup.Renderer.meta.render[]

---@class markup.Renderer.props : markup.Window.props
---@field body markup.Element.children
---@field buttons markup.Element[]

---@class markup.Renderer : markup.Window
---@field protected super markup.Window
---@field protected _ markup.Renderer.props
---@field reconciler markup.Reconciler
---@field render_tree markup.Render.Tree
---@field root markup.Renderer.Root
---@field _meta markup.Renderer.meta
---@field win markup.Window
local M = {}
M.__index = M
-- self = setmetatable(win, { __index = Renderer })

---@param opts? markup.Window.config
function M:new(opts)
	self = setmetatable({}, M)

	self.win = Window.new(opts)

	return self
end

---@param element markup.Element|markup.Element[]
function M:bind(element)
	if type(element) == "function" then
		element = element()
	end
	self.root = RendererFactory.create_root(self, element)
end

---@param element? markup.Element|markup.Element[]
function M:render(element)
	if element then
		self:bind(element)
	end
	self.reconciler = Reconciler()
	-- self.render_tree = RenderTree:new(self)

	self:rerender()
end

function M:rerender()
	vim.api.nvim_buf_call(self.bufnr, function()
		vim.api.nvim_buf_clear_namespace(0, self.ns, 0, -1)
		self.reconciler:reconcile(self.root)
		self:build()
		self:layout()
		self:paint()
	end)
	vim.api.nvim__redraw({ buf = self.bufnr, flush = true })
end

function M:build()
	self:render_root():build()
end

function M:layout()
	self:render_root():layout()
end

function M:paint()
	local mbox = self:render_root():margin_box_size()

	local lines = {}
	local fill = (" "):rep(mbox.width)
	for i = 1, mbox.height do
		lines[i] = fill
	end
	vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)

	self:traverse_and_paint(0, 0, self:render_root())
end

---(x, y) are the coordinates of the parent margin box
---@param x integer
---@param y integer
---@param box markup.Render.Box
function M:traverse_and_paint(x, y, box)
	if box:is("text") then
		box:paint(self, x, y)
		return
	end

	local props = box.props
	local cx = x + props.margin_left + props.padding_left
	local cy = y + props.margin_top + props.padding_top
	for _, child in box:iter_children() do
		self:traverse_and_paint(cx + child.ox, cy + child.oy, child)
	end

	if Markup.debug_mode then
		box:debug_paint_margin(self, x, y)
		box:debug_paint_padding(self, x, y)
	end

	if type(props.style) == "string" or not vim.tbl_isempty(props.style) then
		box:paint(self, x, y)
	end
end

---@return markup.Fiber
function M:fiber_root()
	return self.root.current
end

---@return markup.Node
function M:node_root()
	return self:fiber_root().state_node
end

---@return markup.Render.Box
function M:render_root()
	return self:node_root().render_box
end

return M
