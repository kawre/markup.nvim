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

-- When Neovim last drew the screen. It draws once its queue of events runs dry,
-- which a busy enough UI never lets happen: frames would keep coming and none
-- would show. Views then ask for the screen themselves.
local last_redraw = 0
api.nvim_set_decoration_provider(api.nvim_create_namespace("markup_redraws"), {
	on_start = function()
		last_redraw = vim.uv.hrtime()
	end,
})

--- Draws the screen if it has not been drawn for longer than a frame.
local function keep_drawing()
	local fps = Markup.animate.fps
	local frame = fps == math.huge and 8 or math.max(1000 / fps, 8)
	if (vim.uv.hrtime() - last_redraw) / 1e6 > frame then
		last_redraw = vim.uv.hrtime()
		vim.cmd("redraw")
	end
end

---@class markup.view.opts
---@field snap? boolean|"text" keep the cursor on interactive nodes, like a menu,
--- or with `"text"` on those and on text, like a document. Text under an element
--- with `snap = false` is passed over.
---@field hide_cursor? boolean hide the cursor in normal mode while in this window,
--- for views that show where it is by themselves
---@field press_key? string|string[]|false the keys that press what is under the
--- cursor, as a click does: `<CR>` unless set. Over anything without `on_press`
--- they do what they always do. `false` binds none.

---@param win markup.window
---@param opts? markup.view.opts
function M:new(win, opts)
	opts = opts or {}
	self.win = win
	self.snap_text = opts.snap == "text"
	self.hide_cursor = opts.hide_cursor
	Markup.views[self] = true
	self.ns = api.nvim_create_namespace(("markup_view_[%s]"):format(win.id))
	self.laid_width = self:width()
	self.engine = Markup.core.create_engine(self.laid_width)
	self.commands = protocol.commands()
	self.handlers = {}
	self.clicks = {} ---@type table<integer, "single"|"double"|false>
	self.hover_handlers = {}
	self.images = {} ---@type table<integer, { data: string, width: integer, height: integer, placed?: integer, at?: string }>
	self.key_stacks = {}
	self:bind_press(opts.press_key)
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
			-- Laid out again whatever changed, which also keeps the scroll where
			-- it was when only the height did.
			self:sync_width(true)
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
		self:place_images()
	end, { pattern = "*" })

	-- Images are drawn on the screen, so anything that moves the window moves
	-- them, and a window out of sight takes them away.
	for _, event in ipairs({ "VimResized", "TabEnter", "WinClosed", "WinNew", "WinResized" }) do
		win:on(event, function()
			vim.schedule(function()
				self:place_images()
			end)
		end, { pattern = "*" })
	end

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

	-- Snapping decides where the cursor sits, and `scrolloff` would push it off
	-- its node near an edge, which turns every scroll into a tug of war. Only
	-- this window gets 0, the global value stays.
	local function release_scrolloff()
		if opts.snap and win:win_valid() then
			for _, name in ipairs({ "scrolloff", "sidescrolloff" }) do
				-- Like `:setlocal`, since `vim.wo` would change the global value too.
				api.nvim_set_option_value(name, 0, { scope = "local", win = win.win })
			end
		end
	end
	release_scrolloff()

	-- A hidden window has no buffer yet, so the first frame waits for it.
	win:on_show(function()
		release_scrolloff()
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

--- Lays out for the window's width if it changed, or `always`, returning
--- whether it did.
---@param always? boolean
---@return boolean
function M:sync_width(always)
	local width = self:width()
	if width == self.laid_width and not always then
		return false
	end
	self.laid_width = width
	self.commands:resize(width)
	self.width_cells(width)
	return true
end

--- Starts over from a blank buffer, which the engine's next frame then fills.
function M:attach()
	self.attached = true
	self.engine:reset_frame()
	self:apply({ { 0, -1, lines = {}, marks = {} } })
	-- A view made before its window opens only now knows how wide it is.
	self:sync_width()
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
	-- The engine can be a frame ahead of the buffer, with rows the buffer does
	-- not have yet. The cursor waits for them.
	if not target_row or target_row >= api.nvim_buf_line_count(self.win.buf) then
		return
	end

	-- Scrolling pushes the cursor along, which is when the row it was on went out
	-- of sight. Pulling it back to a node out of sight would undo the scroll, so
	-- it stays until a node comes into view. Moving onto something just past
	-- the edge is different, and scrolls to it as usual.
	local top, bottom = vim.fn.line("w0") - 1, vim.fn.line("w$") - 1
	local function visible(at)
		return at >= top and at <= bottom
	end
	if not visible(from[1]) and not visible(target_row) then
		self.cursor = { row, col }
		return
	end

	self.cursor = { target_row, target_col }
	if target_row ~= row or target_col ~= col then
		local byte = vim.fn.virtcol2col(self.win.win, target_row + 1, target_col + 1) - 1
		api.nvim_win_set_cursor(self.win.win, { target_row + 1, math.max(byte, 0) })
	end

	-- With nothing more that way, show what is there instead, or it could never
	-- be seen: the cursor has to stay on screen.
	local stuck = target_row == from[1] and target_col == from[2] and row ~= from[1]
	if stuck then
		local down = row > from[1]
		if down and bottom + 1 < api.nvim_buf_line_count(self.win.buf) then
			vim.cmd("normal! \5")
		elseif not down and top > 0 then
			vim.cmd("normal! \25")
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
	else
		-- Another view hid it, and its own WinEnter may run after this one, so
		-- this view takes it over rather than let that one give it back.
		cursor_owner = self
	end
end

---@param id integer
---@param image? { data: string, width: integer, height: integer }
function M:set_image(id, image)
	local current = self.images[id]
	if current and current.placed and (not image or image.data ~= current.data) then
		Markup.image.resolve().del(current.placed)
		current.placed = nil
	end

	if image then
		image.placed = current and current.data == image.data and current.placed or nil
		image.at = current and image.placed and current.at or nil
	end
	self.images[id] = image
end

--- Screen rectangles, from one, of the floats above `win`: the terminal draws
--- images over everything, so an image under one of them has to go.
---@param win integer
---@return { top: integer, left: integer, bottom: integer, right: integer }[]
local function covers(win)
	local own = api.nvim_win_get_config(win)
	local level = own.relative ~= "" and (own.zindex or 50) or nil
	local rects = {}
	for _, other in ipairs(api.nvim_tabpage_list_wins(0)) do
		local config = api.nvim_win_get_config(other)
		if
			other ~= win
			and config.relative ~= ""
			and not config.hide
			and (not level or (config.zindex or 50) > level)
		then
			local row, col = unpack(api.nvim_win_get_position(other))
			local border = config.border
			local edge = (
				type(border) == "table" and #border > 0
				or (type(border) == "string" and border ~= "none" and border ~= "")
			)
					and 1
				or 0
			rects[#rects + 1] = {
				top = row + 1 - edge,
				left = col + 1 - edge,
				bottom = row + api.nvim_win_get_height(other) + edge,
				right = col + api.nvim_win_get_width(other) + edge,
			}
		end
	end
	return rects
end

--- Shows each image over its box, moves it with the box, and takes it away
--- when the box is out of sight or cut, since an image cannot be cut, or when a
--- float is over it.
function M:place_images()
	if next(self.images) == nil or not Markup.image.available() then
		return
	end

	local backend = Markup.image.resolve()
	local info = self.win:win_valid()
		and api.nvim_win_get_tabpage(self.win.win) == api.nvim_get_current_tabpage()
		and vim.fn.getwininfo(self.win.win)[1]
	local leftcol = info
			and api.nvim_win_call(self.win.win, function()
				return vim.fn.winsaveview().leftcol
			end)
		or 0

	local over = info and covers(self.win.win) or {}

	for id, image in pairs(self.images) do
		local where
		if info then
			local x, y, width, height, whole = self.engine:visible_rect(id)
			local top, bottom = info.topline - 1, info.botline - 1
			local col = x and x - leftcol
			local inside = x
				and whole
				and y >= top
				and y + height - 1 <= bottom
				and col >= 0
				and col + width <= info.width - info.textoff
			if inside then
				where = {
					row = info.winrow + y - top,
					col = info.wincol + info.textoff + col,
					width = image.width,
					height = image.height,
				}
				for _, rect in ipairs(over) do
					if
						rect.top <= where.row + where.height - 1
						and rect.bottom >= where.row
						and rect.left <= where.col + where.width - 1
						and rect.right >= where.col
					then
						where = nil
						break
					end
				end
			end
		end

		if where then
			local at = ("%d:%d:%d:%d"):format(where.row, where.col, where.width, where.height)
			if not image.placed then
				image.placed = backend.set(image.data, where)
			elseif image.at ~= at then
				backend.set(image.placed, where)
			end
			image.at = at
		elseif image.placed then
			backend.del(image.placed)
			image.placed, image.at = nil, nil
		end
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
	if self.destroyed then
		return
	end
	reactive.after_flush(self.commit_job)
end

---@param id integer
---@param handler? function
---@param click? "single"|"double"|false which click of the mouse presses it, single by default
function M:set_handler(id, handler, click)
	self.handlers[id] = handler
	self.clicks[id] = handler and (click == nil and "single" or click) or nil
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
	-- Nothing else may commit for a while, and the old frame would stay up.
	self:request_commit()
end

--- Stops everything and forgets the view. The window is left to its owner.
function M:destroy()
	for id in pairs(self.images) do
		self:set_image(id, nil)
	end
	self.hide_cursor = false
	self:release_cursor()
	self:unmount()
	self:commit()
	self.destroyed = true
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
	if self.destroyed then
		return
	end
	-- Neovim only says a window was resized when it gets round to drawing, which
	-- a busy view can keep it from for good, so every frame checks for itself.
	if self.attached then
		self:sync_width()
	end
	local commands = self.commands
	local len = commands.len
	commands.len = 0

	local started = vim.uv.hrtime()
	local frame = self.engine:commit(commands.ops, len)
	local stats = self.stats
	stats.engine = (vim.uv.hrtime() - started) / 1e6
	stats.commands = len

	stats.layout, stats.paint, stats.diff = frame.layout, frame.paint, frame.diff

	-- What the engine left out, each said once, since it is a bug somewhere
	-- that would otherwise say it on every frame.
	if frame.errors then
		self.said = self.said or {}
		for _, message in ipairs(frame.errors) do
			if not self.said[message] then
				self.said[message] = true
				local text = ("markup: a command was left out: %s"):format(message)
				vim.notify(text, vim.log.levels.ERROR)
			end
		end
	end

	started = vim.uv.hrtime()
	stats.lines = self.attached and self:apply(frame.patches) or 0
	stats.apply = (vim.uv.hrtime() - started) / 1e6
	if stats.lines > 0 then
		keep_drawing()
	end

	for _, listener in ipairs(self.commit_listeners) do
		listener()
	end

	self:update_hover()
	self:place_images()

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
	-- A closed window lets go of its buffer, though what is still running keeps
	-- committing. Opening it again starts over from a blank buffer.
	if #patches == 0 or not buf or not api.nvim_buf_is_valid(buf) then
		return 0
	end

	-- Writes from the API all join one undo step, as nothing typed in between
	-- closes it, so with undo on every frame would keep growing it forever.
	-- Nothing undoes into a view anyway.
	if self.undo_off ~= buf then
		self.undo_off = buf
		vim.bo[buf].undolevels = -1
	end

	-- Neovim keeps a cursor at the same byte of its line when the line is
	-- replaced, and puts it back at the top when the lines around it are, so
	-- with text of wide characters changing on every frame the cursor would
	-- wander, or jump to the start, and take the scroll along. Every window
	-- showing the buffer keeps where it was on screen instead.
	local windows = {}
	self.wanted = self.wanted or {} ---@type table<integer, { lnum: integer, at: integer }>
	for _, win in ipairs(vim.fn.win_findbuf(buf)) do
		windows[win] = api.nvim_win_call(win, function()
			local view = vim.fn.winsaveview()
			-- A row the buffer was too short for comes back with the lines,
			-- unless the cursor has moved since.
			local wanted = self.wanted[win]
			if wanted and wanted.at == view.lnum then
				view.lnum = wanted.lnum
			end
			self.wanted[win] = nil
			return view
		end)
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

	local count = api.nvim_buf_line_count(buf)
	for win, view in pairs(windows) do
		if api.nvim_win_is_valid(win) then
			api.nvim_win_call(win, function()
				local lnum = math.min(view.lnum, count)
				if lnum < view.lnum then
					self.wanted[win] = { lnum = view.lnum, at = lnum }
				end
				-- The column wanted rather than the one it is at, which a line
				-- that was short for a frame would have pulled in for good.
				-- After `$` that is the end of the line, however long it gets.
				local virtcol = view.curswant >= vim.v.maxcol and math.huge or view.curswant + 1
				local last = vim.fn.virtcol({ lnum, "$" }) - 1
				view.lnum = lnum
				view.col = math.max(
					vim.fn.virtcol2col(win, lnum, math.min(virtcol, math.max(last, 1))) - 1,
					0
				)
				view.topline = math.min(view.topline, count)
				vim.fn.winrestview(view)
			end)
		end
	end
	return total
end

--- Innermost interactive node under the cursor.
---@return integer?
function M:node_at_cursor()
	local cursor = api.nvim_win_get_cursor(self.win.win)
	local col = vim.fn.virtcol(".") - 1
	return self.engine:node_at(cursor[1] - 1, col)
end

--- Presses what is under the mouse, which `mouse` from `getmousepos()` points at,
--- if it takes this kind of click.
---@param mouse table
---@param kind? "single"|"double" any when left out
---@return boolean pressed
function M:click(mouse, kind)
	if not self.win:win_valid() then
		return false
	end

	local info = vim.fn.getwininfo(self.win.win)[1]
	local leftcol = api.nvim_win_call(self.win.win, function()
		return vim.fn.winsaveview().leftcol
	end)

	local id = self.engine:node_at(mouse.line - 1, mouse.wincol - 1 - info.textoff + leftcol)
	local handler = id and self.handlers[id]
	if not handler or (kind and self.clicks[id] ~= kind) then
		return false
	end

	handler()
	reactive.flush()
	return true
end

--- The release ends each click. A double click is <LeftMouse> <LeftRelease>
--- <2-LeftMouse> <2-LeftRelease>, and Neovim selects the word again on the last
--- one, so pressing on <2-LeftMouse> and ending the selection there left it
--- selected once the button came up.
local CLICKS = {
	[vim.keycode("<LeftRelease>")] = "single",
	[vim.keycode("<2-LeftRelease>")] = "double",
}

--- Presses whatever was clicked, in whichever view holds it, when the view
--- presses on that kind of click. One listener for every view, since a mapping
--- only reaches the window that already has the focus, and windows that cannot
--- have it, such as some floats, never do.
---@param kind "single"|"double"
local function on_click(kind)
	local selecting = vim.fn.mode():match("^[vV\22]")
	-- A release that ends a selection is for the text, not for what is under it.
	if kind == "single" and selecting then
		return
	end

	local mouse = vim.fn.getmousepos()
	if mouse.winid == 0 or mouse.line == 0 then
		return
	end

	-- More than one view may have been made for a window, so each gets a go.
	for view in pairs(Markup.views) do
		if view.win.win == mouse.winid and view:click(mouse, kind) then
			-- Neovim selects the word on a double click, which a press leaves out.
			-- This runs once the last key of the click was seen, which can be
			-- before or after Neovim has handled it, so the selection is ended now
			-- if it is there, and again once Neovim has handled what was typed.
			-- Once, so a selection made on purpose later stays.
			if kind == "double" then
				local function deselect()
					if vim.fn.mode():match("^[vV\22]") then
						api.nvim_feedkeys(vim.keycode("<Esc>"), "nx", false)
					end
				end
				deselect()
				api.nvim_create_autocmd("SafeState", { once = true, callback = deselect })
			end
			return
		end
	end
end

vim.on_key(function(key)
	local kind = CLICKS[key]
	if kind then
		vim.schedule(function()
			on_click(kind)
		end)
	end
end, api.nvim_create_namespace("markup_clicks"))

--- Binds the keys that press, under whatever `m.use_key` binds to them later:
--- a component can take one over while it is mounted.
---@param keys? string|string[]|false
function M:bind_press(keys)
	if keys == false then
		return
	end
	keys = keys or "<CR>"
	for _, lhs in ipairs(type(keys) == "table" and keys or { keys }) do
		local stack = {
			{
				fn = function()
					if not self:press() then
						-- Nothing to press: the key keeps its own meaning.
						api.nvim_feedkeys(vim.keycode(lhs), "n", false)
					end
				end,
			},
		}
		self.key_stacks["n " .. lhs] = stack
		self.win:map("n", lhs, function()
			stack[#stack].fn()
		end)
	end
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
