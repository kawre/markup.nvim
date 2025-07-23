---@class markup.renderer.opts
---@field index integer

---@alias markup.renderer.event "confirm" | "key"

---@class markup.renderer
---@field protected opts markup.renderer.opts
---@field reconciler markup.reconciler
---@field root any
---@field win markup.window
---@field private observers table<string, table>
---@field fps integer
---@overload fun(opts?: markup.window.config): markup.renderer
local M = Markup.object()

---@param opts? markup.window.config
function M:new(opts)
	opts = opts or {}
	opts.on_buf = function(win)
		vim.keymap.set("n", "<CR>", function()
			if self.observers.confirm then
				for node, cb in pairs(self.observers.confirm) do ---@cast node markup.node
					local box = node.box
					local c = vim.api.nvim_win_get_cursor(self.win.win)

					if box and box:in_range(c[2], c[1] - 1) then
						cb()
					end
				end
			end
		end, { buffer = win.buf, silent = true })
	end
	opts.on_win = function(win)
		Markup.renderers[win.win] = self
	end

	self.win = Markup.window(opts)
	self.ns = vim.api.nvim_create_namespace("markup_renderer_" .. self.win.id)
	self.reconciler = Markup.reconciler(self)
	self.observers = {}

	-- self.win:on({ "WinResized", "VimResized" }, function()
	-- 	if self.root then
	-- 		self.root.width = vim.api.nvim_win_get_width(self.win.win)
	-- 		self.root.height = vim.api.nvim_win_get_height(self.win.win)
	-- 	end
	-- 	self:render()
	-- end)
	-- self.win:on({ "BufAdd", "BufWinEnter" }, function()
	-- 	self:render()
	-- end)

	-- self.win:on("BufAdd", function()
	-- 	Markup.log("bufenter")
	-- 	vim.keymap.set("n", "<CR>", function()
	-- 		if self.observers.confirm then
	-- 			for node, cb in pairs(self.observers.confirm) do ---@cast node markup.node
	-- 				local box = node.box
	-- 				local c = vim.api.nvim_win_get_cursor(self.win.win)
	-- 				if box:in_range(c[2], c[1] - 1) then
	-- 					cb()
	-- 				end
	-- 			end
	-- 		end
	-- 	end, { buffer = self.win.buf, silent = true })
	-- end)
end

---@param element any
function M:bind(element)
	element = Markup.util.call(element)
	self.rootf = Markup.factory.fiber.root(element)
	self.root = Markup.factory.box.root(self)
end

---@param element? any
function M:render(element)
	if element then
		self:bind(element)
	end
	assert(self.rootf, "Renderer root not bound. Call :render(element) to bind the root element.")
	self.first_render = true
	self:rerender()
end

function M:rerender()
	local elapsed, fps = Markup.util.benchmark(function()
		self.reconciler:reconcile()
		self:build()
		self:layout()
		self:paint()
	end)

	self.stats = { fps = fps, elapsed = elapsed }

	vim.api.nvim_exec_autocmds("User", { pattern = "MarkupRender" .. self.win.id })
	self.first_render = false
end

function M:build()
	local root = self:render_root()

	-- if self.first_render then
	-- 	root:build()
	-- else
	root:reflow()
	-- end
end

function M:layout()
	self:render_root():layout()
end

local str_cache = {}

function M:_paint_with_concat_lines()
	local mbox = self:render_root():margin_box_size()

	-- local fill = (" "):rep(mbox.width)
	-- for i = 1, mbox.height do
	-- 	lines[i] = fill
	-- end
	-- vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)

	self.lines = {}
	self.extmarks = {}
	self:traverse_and_paint(0, 0, self:render_root())

	local l = {}
	for y, chunks in pairs(self.lines) do
		local line = {}

		table.sort(chunks, function(a, b)
			return a.x <= b.x
		end)

		local k = 0
		for _, chunk in ipairs(chunks) do
			local diff = chunk.x - k
			if diff > 0 then
				if not str_cache[diff] then
					str_cache[diff] = (" "):rep(diff)
				end
				table.insert(line, str_cache[diff])
			end
			table.insert(line, chunk.word)
			k = chunk.x + chunk.width
		end
		table.insert(l, table.concat(line))
	end

	vim.api.nvim_buf_clear_namespace(0, self.ns, 0, -1)
	vim.api.nvim_buf_set_lines(0, 0, -1, false, l)

	for _, extmark in ipairs(self.extmarks) do
		vim.api.nvim_buf_set_extmark(0, self.ns, extmark.line, extmark.col, {
			strict = false,
			end_col = extmark.end_col,
			hl_eol = true,
			hl_group = extmark.hl_group,
			hl_mode = "combine",
		})
	end
end

function M:paint()
	vim.api.nvim_buf_call(self.win.buf, function()
		local mbox = self:render_root():margin_box_size()

		local lines = {}
		local fill = (" "):rep(mbox.width)
		for i = 1, mbox.height do
			lines[i] = fill
		end
		vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)

		self:traverse_and_paint(0, 0, self:render_root())
	end)
	-- vim.api.nvim__redraw({ win = self.win.win, flush = true })
end

---(x, y) are the coordinates of the parent margin box
---@param x integer
---@param y integer
---@param box markup.box
function M:traverse_and_paint(x, y, box)
	box.wx = x
	box.wy = y

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

---@param event markup.renderer.event
---@param spec any
---@param cb function
function M:subscribe(event, spec, cb)
	if not self.observers[event] then
		self.observers[event] = {}
	end

	if event == "confirm" then
		self.observers[event][spec] = cb
	elseif event == "key" then
		self.observers[event][spec] = cb
	end
end

---@return markup.box
function M:render_root()
	return self:node_root().box
end

return M
