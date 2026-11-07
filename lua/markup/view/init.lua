--- Connects a window to the engine.
---
--- Effects record commands while they run. One commit per flush sends them to
--- the engine, and the patches that come back are the only buffer writes.

local protocol = require("markup.view.protocol")
local reactive = require("markup.reactive")
local mount = require("markup.view.mount")
local hl = require("markup.view.hl")

local api = vim.api

---@class markup.view.stats
---@field commands integer values sent in the last commit
---@field lines integer lines rewritten by the last commit
---@field layout number ms
---@field paint number ms
---@field diff number ms
---@field engine number ms spent inside the engine call
---@field apply number ms spent writing the buffer

---@class markup.view
---@field win markup.window
---@field stats markup.view.stats
---@field commands markup.view.commands
---@overload fun(win: markup.window): markup.view
local M = Markup.object()

--- Context key that holds the view of the current component.
M.CONTEXT = "markup.view"

local MARK = { end_col = 0, hl_group = "", hl_mode = "combine", hl_eol = true }

---@class markup.view.opts
---@field snap? boolean|"text" keep the cursor on interactive nodes, like a menu,
--- or with `"text"` on those and on text, like a document
---@field hide_cursor? boolean hide the cursor in normal mode while in this window,
--- for views that show where it is by themselves

---@param win markup.window
---@param opts? markup.view.opts
function M:new(win, opts)
	opts = opts or {}
	self.win = win
	self.snap_text = opts.snap == "text"
	self.hide_cursor = opts.hide_cursor
	Markup.views[self] = true
	self.ns = api.nvim_create_namespace(("markup_view_[%s]"):format(win.id))
	self.engine = Markup.core.create_engine(self:width())
	self.commands = protocol.commands()
	self.handlers = {}
	self.hover_handlers = {}
	self.commit_listeners = {}
	self.next_commit = {}
	self.fixed = {} ---@type markup.view.fixed[]
	self.top_row = reactive.signal(0)
	self.width_cells = reactive.signal(self:width())
	self.stats = { commands = 0, lines = 0, layout = 0, paint = 0, diff = 0, engine = 0, apply = 0 }
	self.last_id = protocol.ROOT
	self.commit_job = function()
		self:commit()
	end

	win:on("WinResized", function()
		if win:valid() and vim.tbl_contains(vim.v.event.windows, win.win) then
			self.commands:resize(self:width())
			self.width_cells(self:width())
			self:request_commit()
		end
	end, { pattern = "*" })

	if opts.hide_cursor then
		win:on("WinEnter", function()
			self:sync_cursor()
		end, { pattern = "*" })
	end

	win:on("WinScrolled", function()
		self:update_scroll()
	end, { pattern = "*" })

	if opts.snap == "text" then
		win:on("WinEnter", function()
			self:snap_cursor()
			self:update_hover()
		end, { buf = true })
	end

	win:on("CursorMoved", function()
		if opts.snap then
			self:snap_cursor()
		end
		self:update_hover()
	end, { buf = true })

	-- A hidden window has no buffer yet, so the first frame waits for it.
	win:on_show(function()
		self:attach()
	end)
	if win:valid() then
		self:attach()
	end
end

--- Width to lay out at, which hidden windows can only estimate.
---@return integer
function M:width()
	return self.win:win_valid() and api.nvim_win_get_width(self.win.win) or vim.o.columns
end

--- Starts over from a blank buffer, which the engine's next frame then fills.
function M:attach()
	self.attached = true
	self.engine:reset_frame()
	self:apply({ { 0, -1, lines = {}, marks = {} } })
	self.commands:resize(self:width())
	self:request_commit()
end

--- Keeps the cursor on interactive nodes.
function M:snap_cursor()
	if not self.win:valid() or api.nvim_get_current_win() ~= self.win.win then
		return
	end

	local cursor = api.nvim_win_get_cursor(self.win.win)
	local row, col = cursor[1] - 1, vim.fn.virtcol(".") - 1
	local from = self.cursor or { row, col }

	local target_row, target_col = self.engine:snap(from[1], from[2], row, col, self.snap_text)
	if target_row then
		self.cursor = { target_row, target_col }
		if target_row ~= row or target_col ~= col then
			local byte = vim.fn.virtcol2col(self.win.win, target_row + 1, target_col + 1) - 1
			api.nvim_win_set_cursor(self.win.win, { target_row + 1, math.max(byte, 0) })
		end
	end
end

--- `guicursor` from before hiding it, and the view that hides it.
local shown_cursor, cursor_owner ---@type string?, markup.view?

--- Shows the cursor again, if this view hid it.
function M:release_cursor()
	if cursor_owner == self then
		vim.o.guicursor = shown_cursor
		shown_cursor, cursor_owner = nil, nil
	end
end

--- Hides the cursor while this window is the current one.
function M:sync_cursor()
	if not (self.win:win_valid() and api.nvim_get_current_win() == self.win.win) then
		return self:release_cursor()
	end

	if not cursor_owner then
		shown_cursor, cursor_owner = vim.o.guicursor, self
		api.nvim_set_hl(0, "MarkupHiddenCursor", { blend = 100, nocombine = true })
		vim.o.guicursor = shown_cursor .. ",n:MarkupHiddenCursor"
	end
end

--- Width of the window. Reading it tracks resizes.
---@return integer
function M:columns()
	return self.width_cells()
end

--- Rows scrolled past the top of the window. Reading it tracks the scrolling.
---@return integer
function M:scroll()
	return self.top_row()
end

function M:update_scroll()
	if self.win:win_valid() then
		self.top_row(vim.fn.line("w0", self.win.win) - 1)
		reactive.flush()
	end
end

--- Tells nodes with `on_hover` that the cursor came or went.
function M:update_hover()
	if next(self.hover_handlers) == nil or not self.win:valid() then
		return
	end

	local id = self:node_at_cursor()
	if id == self.hovered then
		return
	end

	local left = self.hover_handlers[self.hovered]
	self.hovered = id
	if left then
		left(false)
	end

	local entered = self.hover_handlers[id]
	if entered then
		entered(true)
	end
	reactive.flush()
end

--- Calls `listener` after the next commit.
---@param listener function
function M:after_commit(listener)
	table.insert(self.next_commit, listener)
	self:request_commit()
end

--- Calls `listener` after every commit.
---@param listener function
function M:on_commit(listener)
	table.insert(self.commit_listeners, listener)
end

---@return integer
function M:next_id()
	self.last_id = self.last_id + 1
	return self.last_id
end

function M:request_commit()
	reactive.after_flush(self.commit_job)
end

---@param id integer
---@param handler? function
function M:set_handler(id, handler)
	self.handlers[id] = handler
end

---@param id integer
---@param handler? fun(hovered: boolean)
function M:set_hover_handler(id, handler)
	self.hover_handlers[id] = handler
end

--- Replaces what the view shows. `content` is rendered once, and stays live
--- until the next call or until `unmount`.
---@param content any
function M:render(content)
	protocol.check_cell_widths()
	self:unmount()

	local ok, err = pcall(function()
		local _, owner = reactive.scope(function()
			reactive.provide(M.CONTEXT, self)
			mount.mount(self, content, protocol.ROOT)
		end)
		self.owner = owner
	end)

	self:request_commit()
	reactive.flush()

	if not ok then
		error(err, 0)
	end
end

function M:unmount()
	if self.owner then
		reactive.dispose(self.owner)
		self.owner = nil
	end
	self.commands:clear(protocol.ROOT)
end

--- Stops everything and forgets the view. The window is left to its owner.
function M:destroy()
	self.hide_cursor = false
	self:release_cursor()
	self:unmount()
	self:commit()
	Markup.views[self] = nil
end

--- The view shown in a window, or the first one in the current tab.
---@param win? integer
---@return markup.view?
function M.find(win)
	win = win or api.nvim_get_current_win()
	local tab_wins = api.nvim_tabpage_list_wins(0)
	local in_tab
	for view in pairs(Markup.views) do
		local id = view.win.win
		if id == win then
			return view
		end
		if not view.devtool and vim.tbl_contains(tab_wins, id) then
			in_tab = in_tab or view
		end
	end
	return in_tab
end

--- Sends pending commands and applies the resulting patches.
function M:commit()
	local commands = self.commands
	local len = commands.len
	commands.len = 0

	local started = vim.uv.hrtime()
	local frame = self.engine:commit(commands.ops, len)
	local stats = self.stats
	stats.engine = (vim.uv.hrtime() - started) / 1e6
	stats.commands = len

	stats.layout, stats.paint, stats.diff = frame.layout, frame.paint, frame.diff

	started = vim.uv.hrtime()
	stats.lines = self.attached and self:apply(frame.patches) or 0
	stats.apply = (vim.uv.hrtime() - started) / 1e6

	for _, listener in ipairs(self.commit_listeners) do
		listener()
	end

	self:update_hover()

	if self.hide_cursor then
		self:sync_cursor()
	end

	local next_commit = self.next_commit
	self.next_commit = {}
	for _, listener in ipairs(next_commit) do
		listener()
	end

	api.nvim_exec_autocmds("User", { pattern = "MarkupViewCommit" .. self.win.id })
end

--- Patch ranges refer to the previous frame, so last to first keeps them valid.
---@param patches table[]
---@return integer lines rewritten
function M:apply(patches)
	local buf, ns = self.win.buf, self.ns
	if #patches == 0 or not api.nvim_buf_is_valid(buf) then
		return 0
	end

	local modifiable = vim.bo[buf].modifiable
	vim.bo[buf].modifiable = true

	local total = 0
	local set_extmark = api.nvim_buf_set_extmark
	local name = hl.name
	for i = #patches, 1, -1 do
		local patch = patches[i]
		local first, last, marks = patch[1], patch[2], patch.marks

		api.nvim_buf_clear_namespace(buf, ns, first, last)
		api.nvim_buf_set_lines(buf, first, last, false, patch.lines)
		total = total + #patch.lines

		for j = 1, #marks, 4 do
			MARK.end_col = marks[j + 2]
			MARK.hl_group = name(marks[j + 3])
			set_extmark(buf, ns, marks[j], marks[j + 1], MARK)
		end
	end

	vim.bo[buf].modifiable = modifiable
	return total
end

--- Innermost interactive node under the cursor.
---@return integer?
function M:node_at_cursor()
	local cursor = api.nvim_win_get_cursor(self.win.win)
	local col = vim.fn.virtcol(".") - 1
	return self.engine:node_at(cursor[1] - 1, col)
end

--- Calls the `on_press` handler under the cursor, returning whether there was one.
---@return boolean
function M:press()
	local handler = self.handlers[self:node_at_cursor()]
	if handler then
		handler()
		return true
	end
	return false
end

return M
