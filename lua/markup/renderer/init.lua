local styles = require("markup.window.styles")
---@class markup.renderer.opts
---@field index integer

---@alias markup.renderer.event "confirm" | "key"

---@class markup.renderer
---@field protected opts markup.renderer.opts
---@field root any
---@field rootf markup.fiber
---@field current? markup.renderer
---@field win markup.window
---@field private observers table<string, table>
---@field is_scheduled boolean
---@field fps integer
---@overload fun(opts?: markup.window.config): markup.renderer
local M = Markup.object()
M.current = nil

---@param opts? markup.window.config
function M:new(opts)
	opts = vim.tbl_deep_extend("keep", opts or {}, styles["renderer"])

	opts.on_win = function(win)
		Markup.renderers[win.win] = self
	end

	self.win = Markup.window(opts)
	self.ns = vim.api.nvim_create_namespace(("markup_renderer_[%s]"):format(self.win.id))
	self.debug_ns =
		vim.api.nvim_create_namespace(("markup_renderer_[%s]_debug"):format(self.win.id))
	self.observers = {}
	self.fps_samples = {}
	self.stats = {}
	self.buttons = {}
	self.keys = {} ---@type table<markup.node, { key: string, cb: function }[]>
	self.cursor = {}

	self.win:on("WinResized", function()
		if self:valid() and vim.tbl_contains(vim.v.event.windows, self.win.win) then
			self:rerender()
		end
	end, { pattern = "*" })

	self.win:on("CursorMoved", function()
		if self:valid() then
			self:handle_cursor_moved()
		end
	end, { buf = true })
end

---@param element any
function M:bind(element)
	self.element = Markup.util.call(element)
end

---@param element? any
function M:render(element)
	if element then
		self:bind(element)
	end

	assert(self.element, "Renderer element not bound. Call :bind(element) to bind the element.")
	self.rootf = Markup.factory.fiber.root(self.element)
	self.root = Markup.factory.box(self.rootf.state_node)
	self.stats = {}

	self:rerender()
end

function M:schedule_rerender()
	if self.is_scheduled then
		return
	end

	self.is_scheduled = true
	vim.schedule(function()
		self:rerender()
		self.is_scheduled = false
	end)
end

function M:rerender()
	assert(self.rootf, "Renderer root not bound. Call :render(element) to bind the root element.")
	M.current = self

	local elapsed = Markup.util.benchmark(function()
		self.rootf = Markup.reconciler(self.rootf)
		self:build()
		self:layout()
		self:paint()
	end)

	self:track_fps(elapsed)

	-- vim.api.nvim__redraw({ win = self.win.win, flush = true })
	vim.api.nvim_exec_autocmds("User", { pattern = "MarkupRender" .. self.win.id })
	M.current = nil
end

function M:track_fps(elapsed)
	if vim.tbl_isempty(self.stats) then
		self.stats.first_elapsed = elapsed
	end
	table.insert(self.fps_samples, 1e3 / elapsed)
	if #self.fps_samples > 60 then
		table.remove(self.fps_samples, 1)
	end

	local sum = 0
	for _, v in ipairs(self.fps_samples) do
		sum = sum + v
	end
	local avg_fps = sum / #self.fps_samples

	self.stats.fps = avg_fps
	self.stats.elapsed = elapsed
end

function M:build()
	self:render_root():reflow()
end

function M:layout()
	self:render_root():layout({ available_width = vim.api.nvim_win_get_width(self.win.win) })
end

local str_cache = {}

function M:_paint_with_concat_lines()
	local mbox = self:render_root():get_box_size("margin")

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
		vim.api.nvim_buf_clear_namespace(0, self.ns, 0, -1)
		vim.api.nvim_buf_clear_namespace(0, self.debug_ns, 0, -1)

		local cbox = self:render_root():get_box_size("content")

		local lines = {}
		local fill = (" "):rep(cbox.width)
		for i = 1, cbox.height do
			lines[i] = fill
		end
		vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)

		self:traverse_and_paint(0, 0, self:render_root())
	end)
	-- vim.api.nvim__redraw({ buf = self.win.buf, flush = true, valid = true })
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

	local props = box.computed
	local cx = x + props.margin_left + props.padding_left
	local cy = y + props.margin_top + props.padding_top
	for _, child in box:iter_children() do
		self:traverse_and_paint(cx + child.ox, cy + child.oy, child)
	end

	if Markup.config.debug then
		box:debug_paint_margin(self, x, y)
		box:debug_paint_padding(self, x, y)
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
	return self.rootf.state_node
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
	return self.rootf.state_node.box
end

function M:handle_cursor_moved()
	if self.rootf and not self.win:valid() then
		return
	end

	local cursor = vim.api.nvim_win_get_cursor(self.win.win)
	local new_row, new_col = cursor[1], cursor[2]
	local prev_row, prev_col = unpack(self.cursor.prev or { new_row, new_col })

	local stack = Markup.collection.stack()
	stack:push(self:render_root())
	local buttons = {} ---@type markup.box[]

	local row = new_row - 1
	local prow = prev_row - 1

	while stack.len > 0 do
		local box = stack:pop() ---@cast box markup.box
		local mrange = box:get_box_range("margin")
		assert(mrange, "Box must have a margin box range")

		-- Directional pruning
		local skip = false
		if prow < row and mrange.bottom < row then
			-- moved down, box ends above
			skip = true
		elseif prow > row and mrange.top > row then
			-- moved up, box starts below
			skip = true
		elseif prev_col < new_col and mrange.right < new_col then
			-- moved right, box ends left
			skip = true
		elseif prev_col > new_col and mrange.left > new_col then
			-- moved left, box starts right
			skip = true
		end

		if not skip then
			if box.node.tag_name == "button" then
				table.insert(buttons, box)
			else
				for _, child in box:iter_children() do
					stack:push(child)
				end
			end
		end
	end

	if #buttons == 0 then
		if self.cursor.prev then
			vim.api.nvim_win_set_cursor(self.win.win, self.cursor.prev)
		end
		return
	end

	table.sort(buttons, function(a, b)
		return a:distance_to(new_col, new_row - 1) < b:distance_to(new_col, new_row - 1)
	end)

	local target = buttons[1]
	local mrange = target:get_box_range("margin")
	assert(mrange, "Target box must have a margin box range")

	-- If inside the new button, do nothing
	if target:in_range(new_col, row, mrange) then
		self.cursor.prev = { new_row, new_col }
		return
	end

	-- Clamp col & row inside the target box
	local clamped_col = math.max(mrange.left, math.min(new_col, mrange.right))
	local clamped_row = math.max(mrange.top, math.min(row, mrange.bottom))

	-- Convert back to 1-indexed for win_set_cursor
	self.cursor.prev = { clamped_row + 1, clamped_col }
	vim.api.nvim_win_set_cursor(self.win.win, self.cursor.prev)
end

function M:valid()
	return self.element and self.root and self.rootf and self.win:valid()
end

return M
