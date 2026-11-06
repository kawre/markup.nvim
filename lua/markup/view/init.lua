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
---@field snap? boolean keep the cursor on interactive nodes, like a menu

---@param win markup.window
---@param opts? markup.view.opts
function M:new(win, opts)
	opts = opts or {}
	self.win = win
	Markup.views[self] = true
	self.ns = api.nvim_create_namespace(("markup_view_[%s]"):format(win.id))
	self.engine = Markup.core.create_engine(self:width())
	self.commands = protocol.commands()
	self.handlers = {}
	self.commit_listeners = {}
	self.fixed = {} ---@type markup.view.fixed[]
	self.stats = { commands = 0, lines = 0, layout = 0, paint = 0, diff = 0, engine = 0, apply = 0 }
	self.last_id = protocol.ROOT
	self.commit_job = function()
		self:commit()
	end

	win:on("WinResized", function()
		if win:valid() and vim.tbl_contains(vim.v.event.windows, win.win) then
			self.commands:resize(self:width())
			self:request_commit()
		end
	end, { pattern = "*" })

	if opts.snap then
		win:on("CursorMoved", function()
			self:snap_cursor()
		end, { buf = true })
	end

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

	local target_row, target_col = self.engine:snap(from[1], from[2], row, col)
	if target_row then
		self.cursor = { target_row, target_col }
		if target_row ~= row or target_col ~= col then
			local byte = vim.fn.virtcol2col(self.win.win, target_row + 1, target_col + 1) - 1
			api.nvim_win_set_cursor(self.win.win, { target_row + 1, math.max(byte, 0) })
		end
	end
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

--- Replaces what the view shows. `content` is rendered once, and stays live
--- until the next call or until `unmount`.
---@param content any
function M:render(content)
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
