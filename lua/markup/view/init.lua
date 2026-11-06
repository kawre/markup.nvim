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

local MARK = { end_col = 0, hl_group = "", hl_mode = "combine", hl_eol = true }

---@param win markup.window
function M:new(win)
	self.win = win
	Markup.views[self] = true
	self.ns = api.nvim_create_namespace(("markup_view_[%s]"):format(win.id))
	self.engine = Markup.core.create_engine(api.nvim_win_get_width(win.win))
	self.commands = protocol.commands()
	self.handlers = {}
	self.stats = { commands = 0, lines = 0, layout = 0, paint = 0, diff = 0, engine = 0, apply = 0 }
	self.last_id = protocol.ROOT
	self.commit_job = function()
		self:commit()
	end

	-- The engine starts from a blank frame, so the buffer has to match it.
	self:apply({ { 0, -1, lines = {}, marks = {} } })

	win:on("WinResized", function()
		if win:valid() and vim.tbl_contains(vim.v.event.windows, win.win) then
			self.commands:resize(api.nvim_win_get_width(win.win))
			self:request_commit()
		end
	end, { pattern = "*" })
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
	stats.lines = self:apply(frame.patches)
	stats.apply = (vim.uv.hrtime() - started) / 1e6

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
