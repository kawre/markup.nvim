---@class markup.renderer.opts
---@field index integer

---@class markup.renderer: markup.window
---@field protected opts markup.renderer.opts
---@field reconciler markup.reconciler
---@field root any
---@field win markup.window
---@overload fun(opts?: markup.window.config): markup.renderer
local M = Markup.object()

---@param opts? markup.window.config
function M:new(opts)
	self.win = Markup.window(opts)
	self.ns = vim.api.nvim_create_namespace("markup_renderer_" .. self.win.id)

	self.reconciler = Markup.reconciler(self)

	self.win:on("WinResized", function()
		if self.root then
			self.root.width = vim.api.nvim_win_get_width(self.win.win)
			self.root.height = vim.api.nvim_win_get_height(self.win.win)
		end
	end)
end

---@param element any
function M:bind(element)
	element = Markup.util.call_if_callable(element)
	self.rootf = Markup.factory.fiber.root(element)
	self.root = Markup.factory.box.root(self)
end

---@param element? any
function M:render(element)
	if element then
		self:bind(element)
	end
	assert(self.rootf, "Renderer root not bound. Call :render(element) to bind the root element.")
	self:rerender()
end

function M:rerender()
	vim.api.nvim_buf_call(self.win.buf, function()
		vim.api.nvim_buf_clear_namespace(0, self.ns, 0, -1)
		self.reconciler:reconcile()
		self:build()
		self:layout()
		self:paint()
	end)
	vim.api.nvim__redraw({ win = self.win.win, flush = true })
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

	if Markup.config.debug then
		box:debug_paint_margin(x, y)
		box:debug_paint_padding(x, y)
	end

	if type(props.style) == "string" or not vim.tbl_isempty(props.style) then
		box:paint(self, x, y)
	end
end

---@return markup.fiber
function M:fiber_root()
	return self.rootf
end

---@return markup.node
function M:node_root()
	return self:fiber_root().state_node
end

---@return markup.Render.Box
function M:render_root()
	return self:node_root().render_box
end

return M
