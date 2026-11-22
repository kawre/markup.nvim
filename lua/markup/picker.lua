--- A list that narrows as you type, to pick one item from.
---
--- `Markup.picker(opts)` opens one: a prompt over a list in a float, or a
--- column beside the editor with `layout = "right"`, and so on. Behind it is
--- `Markup.picker.new(opts)`, which holds what a picker does, the query, the
--- matches, the selection and every key, and draws into whatever windows it
--- is given: a plugin with a look of its own keeps all of the behaviour.
---
--- Matching is nucleo's, the matcher of the Helix editor, in the engine, with
--- fzf's syntax: `^start`, `end$`, `'exact` and `!not`. A long list is matched
--- on a thread of its own, so typing never waits for it, and a query that
--- only adds to the last one searches what that one found. Without the engine,
--- or with `filter` of the caller's own, it matches in Lua. Only the rows that
--- fit the list are ever mounted, so many thousands of items are fine.
---
--- Keys, as the Snacks picker has them. In insert mode: <CR> picks;
--- <Down>/<Up>, <C-j>/<C-k>, <C-n>/<C-p> and <Tab>/<S-Tab> move, going round at
--- the ends; <C-d>/<C-u> scroll half the list, <PageDown>/<PageUp> all of it;
--- <Esc> goes to normal mode (or closes, with `esc = "close"`); <C-c> closes. The
--- rest edit the query, <C-w> included.
---
--- In normal mode the list moves as a buffer would, counts and all: j/k, gg/G,
--- <C-d>/<C-u>, <C-f>/<C-b>, <C-e>/<C-y>, H/M/L and zz/zt/zb. / takes the focus
--- to the list, where the same keys work, and i or / brings it back. i, a and
--- the like go back to typing; q and <Esc> close.
---
--- The selection keeps 'scrolloff' rows from the edges, the mouse wheel
--- scrolls the list by 'mousescroll', and a click picks a row.

local reactive = require("markup.reactive")

local api = vim.api

-- The engine, for its matcher, when it is there.
local native = (function()
	local ok, core = pcall(require, "markup.core")
	return ok and type(core) == "table" and core or nil
end)()

---@class markup.picker.span
---@field [1] string text
---@field [2]? string highlight

---@class markup.picker.item
---@field label string what is shown and matched, with matches highlighted
---@field keywords? string matched as well, but never shown, such as an id
---@field prefix? markup.picker.span[] before the label
---@field suffix? markup.picker.span[] at the end of the row
---@field value any

---@class markup.picker.entry
---@field item any an item, as `items` has it
---@field positions? integer[] characters of its label that matched, from zero

---@class markup.picker.row_context
---@field index integer where the row is in the matches
---@field selected boolean whether it is the selected row
---@field width integer cells the row has
---@field picker markup.picker.instance

---@alias markup.picker.key fun(picker: markup.picker.instance)|{ [1]: fun(picker: markup.picker.instance), mode?: string|string[] }|false

---@class markup.picker.render
---@field row? fun(entry: markup.picker.entry, ctx: markup.picker.row_context): markup.element a row of the list, for items of any shape
---@field empty? fun(picker: markup.picker.instance): markup.element shown when nothing matches

---@class markup.picker.core_opts
---@field items any[]|fun(): any[] read in an effect, so a signal can change them
---@field on_select fun(value: any, item: any) with the item's `value`, or the item when it has none
---@field on_close? fun() when it closes without anything picked
---@field close_on_select? boolean close once something is picked, true by default
---@field auto_close? boolean close when the focus moves to a window that is not the picker's, true by default
---@field filter? fun(items: any[], query: string): markup.picker.entry[] matches, best first, fuzzy by `label` by default; signals it reads filter again when they change
---@field render? markup.picker.render
---@field keys? table<string, markup.picker.key> more keys, or `false` to take one away; normal mode unless `mode` says otherwise
---@field empty? string shown when nothing matches
---@field click? "single"|"double"|false which click picks a row, single by default
---@field esc? "normal"|"close" what <Esc> does while typing, "normal" by default
---@field on_input_leave? fun(picker: markup.picker.instance) when typing ends, however it ends: for an input that only shows while typing
---@field on_focus_input? fun(picker: markup.picker.instance) how to start typing, for an input that is not always there

---@class markup.picker.opts: markup.picker.core_opts
---@field title? string
---@field layout? "float"|"right"|"left"|"bottom"|"top"|fun(picker: markup.picker.instance) where it goes, or a function that makes its windows and attaches them
---@field width? number cells, or a fraction of the editor: 80 by default, 0.4 beside it
---@field height? number rows of the list, or a fraction of the editor: 15 by default, 0.4 above or below
---@field count? boolean show how many match, true by default
---@field prompt? string before the query, "> " by default

---@class markup.picker
local M = {}

local groups = {
	MarkupPickerSelected = { link = "CursorLine" },
	MarkupPickerMatch = { link = "Special" },
	-- Groups are only defaults, so a plugin or colorscheme can restyle them.
	MarkupPickerMarker = { link = "Special" },
	MarkupPickerPrompt = { link = "Special" },
	MarkupPickerCount = { link = "Comment" },
	MarkupPickerEmpty = { link = "Comment" },
	-- As the popup menu draws its scrollbar.
	MarkupPickerScrollbar = { link = "PmenuSbar" },
	MarkupPickerThumb = { link = "PmenuThumb" },
}

local function define_groups()
	for name, definition in pairs(groups) do
		api.nvim_set_hl(0, name, vim.tbl_extend("force", definition, { default = true }))
	end
end

--- Splits a label into runs, marking the characters a query matched.
---@param label string
---@param positions? integer[] character indexes, from zero
---@return markup.picker.span[]
function M.highlight(label, positions)
	if not positions or #positions == 0 then
		return { { label } }
	end

	local matched = {}
	for _, position in ipairs(positions) do
		matched[position] = true
	end

	local spans = {}
	for index, char in ipairs(vim.fn.split(label, "\\zs")) do
		local hl = matched[index - 1] and "MarkupPickerMatch" or nil
		local last = spans[#spans]
		if last and last[2] == hl then
			last[1] = last[1] .. char
		else
			spans[#spans + 1] = { char, hl }
		end
	end
	return spans
end

--- Items matching a query, best first, with the positions that matched.
---@param items markup.picker.item[]
---@param query string
---@return { item: markup.picker.item, positions?: integer[] }[]
function M.filter(items, query)
	if query:match("^%s*$") then
		return vim.tbl_map(function(item)
			return { item = item }
		end, items)
	end

	local candidates = {}
	for index, item in ipairs(items) do
		local text = item.keywords and (item.label .. " " .. item.keywords) or item.label
		candidates[index] = { text = text, index = index }
	end

	local found = vim.fn.matchfuzzypos(candidates, query, { key = "text" })
	local result = {}
	for i, candidate in ipairs(found[1]) do
		result[i] = { item = items[candidate.index], positions = found[2][i] }
	end
	return result
end

---@class markup.picker.instance
---@field opts markup.picker.core_opts
---@field query fun(value?: string): string
---@field selected fun(value?: integer): integer the row selected, from one
---@field offset fun(value?: integer): integer rows scrolled past
---@field rows fun(value?: integer): integer rows the list shows
---@field width fun(value?: integer): integer cells the list has
---@field filtered fun(): markup.picker.entry[] what matches now
---@field closed boolean
local Picker = {}
Picker.__index = Picker

--- The items, read now.
function Picker:items()
	local items = self.opts.items
	return type(items) == "function" and items() or items
end

--- Neovim holds back TextChangedI while keys are still queued, as when typing
--- fast or pasting, so whatever acts on the query reads it first.
function Picker:sync()
	local buf = self.input_buf
	if not (buf and api.nvim_buf_is_valid(buf)) then
		return
	end
	local text = api.nvim_buf_get_lines(buf, 0, 1, false)[1] or ""
	-- Only what was typed since: a query set from code stays until then.
	if text ~= self.typed and text ~= reactive.untrack(self.query) then
		self.typed = text
		self.query(text)
		self:search(text)
		self:to_top()
	end
end

--- Every item as an entry, for a query that matches all of them.
---@param items any[]
function Picker:everything(items)
	if self.all_items ~= items then
		self.all_items = items
		self.all_entries = {}
		for index, item in ipairs(items) do
			self.all_entries[index] = { item = item, native = index }
		end
	end
	return self.all_entries
end

--- The engine's matcher for `items`, made again when they change.
---@param items any[]
function Picker:matcher_for(items)
	if self.native_items ~= items then
		local candidates = {}
		for index, item in ipairs(items) do
			local text = type(item) == "table" and item.label or tostring(item)
			if type(item) == "table" and item.keywords then
				text = text .. " " .. item.keywords
			end
			candidates[index] = text
		end
		self.native = native.create_matcher(candidates)
		self.native_items = items
		self.searched = nil
	end
	return self.native
end

--- Starts matching `query` in the engine. What it finds comes in `found`, at
--- once for a short list, from a thread for a long one.
---@param query string
function Picker:search(query)
	if not self.uses_native then
		return
	end
	local items = reactive.untrack(function()
		return self:items()
	end)
	local matcher = self:matcher_for(items)
	if self.searched == query then
		return
	end
	self.searched = query
	if query:match("^%s*$") then
		self.pending = false
		self.found({ items = items, query = query })
		return
	end

	local function take(indices)
		self.pending = false
		self.found({ items = items, query = query, indices = indices })
	end
	if matcher:start(query) then
		return take(matcher:poll())
	end

	self.pending = true
	if not self.poll_timer then
		self.poll_timer = assert(vim.uv.new_timer())
		self.poll_timer:start(
			2,
			2,
			vim.schedule_wrap(function()
				if self.closed or not self.pending then
					return self:stop_polling()
				end
				local indices = self.native:poll()
				if indices then
					self:stop_polling()
					take(indices)
					reactive.flush()
				end
			end)
		)
	end
end

function Picker:stop_polling()
	if self.poll_timer and not self.poll_timer:is_closing() then
		self.poll_timer:stop()
		self.poll_timer:close()
	end
	self.poll_timer = nil
end

--- What the engine found, as entries, best first.
function Picker:native_entries()
	local items = self:items()
	local found = self.found()
	if not found or found.items ~= items then
		-- Changed items, matched again; meanwhile, what was found before.
		reactive.untrack(function()
			self:search(self.query())
		end)
		found = reactive.untrack(self.found)
		if not found or found.items ~= items then
			return self.last_entries or {}
		end
	end
	if not found.indices then
		return self:everything(items)
	end
	if self.last_found ~= found then
		local entries = {}
		for i, index in ipairs(found.indices) do
			entries[i] = { item = items[index], native = index }
		end
		self.last_found, self.last_entries = found, entries
	end
	return self.last_entries
end

--- The characters of `entry` the query matched, from zero, worked out only
--- for the rows that show.
---@param entry markup.picker.entry
---@return integer[]?
function Picker:positions(entry)
	if entry.positions or not (self.uses_native and entry.native and self.native) then
		return entry.positions
	end
	local query = reactive.untrack(self.query)
	if query:match("^%s*$") then
		return nil
	end
	if entry.positions_for ~= query then
		entry.positions_for = query
		entry.positions = self.native:positions(entry.native, query)
	end
	return entry.positions
end

--- Back to the first row, for matches that are new.
function Picker:to_top()
	self.selected(1)
	self.offset(0)
	self.seen = self.filtered()
end

--- The furthest the list scrolls: its last row at the bottom.
function Picker:max_offset()
	return math.max(#self.filtered() - self.rows(), 0)
end

--- Rows kept between the selection and the edges of the list, as
--- 'scrolloff' keeps them around the cursor.
function Picker:margin()
	return math.max(math.min(vim.o.scrolloff, math.floor((self.rows() - 1) / 2)), 0)
end

--- Scrolls just enough for the selection to show, its margin with it.
function Picker:reveal()
	local index, height, keep = self.selected(), self.rows(), self:margin()
	if index - keep <= self.offset() then
		self.offset(index - keep - 1)
	elseif index + keep > self.offset() + height then
		self.offset(index + keep - height)
	end
	self.offset(math.max(math.min(self.offset(), self:max_offset()), 0))
end

--- Selects row `index`, kept inside the list, and shows it.
function Picker:select(index)
	self:sync()
	local count = #self.filtered()
	if count == 0 then
		return
	end
	self.selected(math.max(math.min(index, count), 1))
	self:reveal()
	reactive.flush()
end

--- Moves by `by` rows, going round past either end, counts too.
function Picker:move(by)
	self:sync()
	local count = #self.filtered()
	if count == 0 then
		return
	end
	self:select((self.selected() + by - 1) % count + 1)
end

--- Scrolls the list by `by` rows, keeping the selection inside what shows.
function Picker:scroll(by)
	self:sync()
	if #self.filtered() == 0 then
		return
	end
	self.offset(math.max(math.min(self.offset() + by, self:max_offset()), 0))
	-- Its margin too, except where the list cannot scroll any further.
	local keep = self:margin()
	local first = self.offset() + 1 + (self.offset() > 0 and keep or 0)
	local last = math.min(self.offset() + self.rows(), #self.filtered())
		- (self.offset() < self:max_offset() and keep or 0)
	self.selected(math.max(math.min(self.selected(), last), first))
	reactive.flush()
end

--- Scrolls and moves together, as <C-d> and <C-f> do in a buffer.
function Picker:page(by)
	self:sync()
	if #self.filtered() == 0 then
		return
	end
	self.offset(math.max(math.min(self.offset() + by, self:max_offset()), 0))
	self:select(self.selected() + by)
end

--- Puts the selection at the top, middle or bottom of the list.
---@param where "top"|"middle"|"bottom"
function Picker:align(where)
	self:sync()
	local height, at = self.rows(), self.selected()
	if where == "top" then
		self.offset(at - 1)
	elseif where == "bottom" then
		self.offset(at - height)
	else
		self.offset(at - math.ceil(height / 2))
	end
	self.offset(math.max(math.min(self.offset(), self:max_offset()), 0))
	reactive.flush()
end

--- Selects the row the list's cursor is on, while the list has the focus:
--- whatever moved the cursor, a click or a motion of Vim's own, moved the
--- selection too.
function Picker:follow_cursor()
	local list = self.list
	if not (list and list:win_valid() and api.nvim_get_current_win() == list.win) then
		return
	end
	local count = #reactive.untrack(self.filtered)
	local index = reactive.untrack(self.offset) + api.nvim_win_get_cursor(list.win)[1]
	if index ~= reactive.untrack(self.selected) and index >= 1 and index <= count then
		self.selected(index)
		reactive.flush()
	end
end

--- The entry selected, if anything matches.
---@return markup.picker.entry?
function Picker:current()
	self:follow_cursor()
	self:sync()
	-- What the newest query finds, not what the one before did.
	if self.pending and self.native then
		local indices = self.native:wait()
		self:stop_polling()
		self.pending = false
		if indices then
			self.found({ items = self:items(), query = self.searched, indices = indices })
		end
	end
	return self.filtered()[self.selected()]
end

--- Picks the selected entry, and closes.
function Picker:confirm()
	local entry = self:current()
	if self.opts.close_on_select ~= false then
		self.picked = entry ~= nil
		self:close()
	end
	if entry then
		local item = entry.item
		local value = type(item) == "table" and item.value
		if value == nil then
			value = item
		end
		self.opts.on_select(value, item)
	end
end

--- Runs `fn` when the picker closes, for the windows a layout made.
function Picker:on_cleanup(fn)
	self.cleanups[#self.cleanups + 1] = fn
end

--- Makes `win` part of the picker: moving to any other window closes it.
function Picker:own(win)
	if win then
		self.owned[win] = true
	end
end

function Picker:close()
	if self.closed then
		return
	end
	self.closed = true

	pcall(api.nvim_del_augroup_by_id, self.group)
	self:stop_polling()
	if vim.fn.mode() == "i" then
		vim.cmd.stopinsert()
	end
	reactive.dispose(self.owner)
	if self.view then
		self.view:destroy()
	end
	for i = #self.cleanups, 1, -1 do
		pcall(self.cleanups[i])
	end
	if api.nvim_win_is_valid(self.origin) then
		pcall(api.nvim_set_current_win, self.origin)
	end
	if not self.picked and self.opts.on_close then
		self.opts.on_close()
	end
end

--- Starts typing: in the input, or as `on_focus_input` says.
function Picker:focus_input()
	self.in_list = false
	if self.opts.on_focus_input then
		return self.opts.on_focus_input(self)
	end
	if self.input_win and api.nvim_win_is_valid(self.input_win) then
		api.nvim_set_current_win(self.input_win)
		vim.cmd.startinsert({ bang = true })
	end
end

--- Takes the focus to the list, where the cursor follows the selection.
function Picker:focus_list()
	if not (self.list and self.list:win_valid()) then
		return
	end
	self.in_list = true
	self.leaving_input = true
	vim.cmd.stopinsert()
	api.nvim_set_current_win(self.list.win)
	self.leaving_input = false
	self:place_cursor()
end

--- Keeps the list's cursor on the selection, for when it has the focus.
function Picker:place_cursor()
	local list = self.list
	if list and list:win_valid() then
		local row = reactive.untrack(self.selected) - reactive.untrack(self.offset)
		local last = api.nvim_buf_line_count(list.buf)
		pcall(api.nvim_win_set_cursor, list.win, { math.max(math.min(row, last), 1), 0 })
	end
end

--- The size the list has, read from its window.
function Picker:measure()
	if self.list and self.list:win_valid() then
		self.rows(math.max(api.nvim_win_get_height(self.list.win), 1))
		self.width(api.nvim_win_get_width(self.list.win))
		self:reveal()
	end
end

local function spans_of(spans)
	local m = require("markup")
	return vim.tbl_map(function(span)
		return m.inline(span[1], span[2])
	end, spans)
end

--- A row of a `markup.picker.item`: its prefix, the label with what matched
--- lit, and its suffix at the end.
---@param entry markup.picker.entry
---@param ctx markup.picker.row_context
function M.row(entry, ctx)
	local m = require("markup")
	local item = entry.item
	local label = {}
	vim.list_extend(label, item.prefix or {})
	local positions = entry.positions
	if ctx.picker then
		positions = ctx.picker:positions(entry)
	end
	vim.list_extend(label, M.highlight(item.label, positions))

	return m.flex({
		white_space = "nowrap",
		justify = "between",
		style = ctx.selected and "MarkupPickerSelected" or nil,
		m.inline({
			shrink = 1,
			overflow_x = "hidden",
			text_overflow = "ellipsis",
			m.inline(ctx.selected and "▌" or " ", "MarkupPickerMarker"),
			m.inline({ margin_left = 1, spans_of(label) }),
		}),
		item.suffix and m.inline({
			shrink = 0,
			margin_left = 1,
			margin_right = 1,
			spans_of(item.suffix),
		}),
	})
end

--- A column as tall as the list, with a thumb for the part that shows.
function Picker:scrollbar(count, height)
	local m = require("markup")
	local thumb = math.max(math.floor(height * height / count + 0.5), 1)
	local span = math.max(count - height, 1)
	local start = math.floor(self.offset() / span * (height - thumb) + 0.5)
	local lines = {}
	for row = 0, height - 1 do
		local on = row >= start and row < start + thumb
		lines[#lines + 1] = m.block({
			m.inline(" ", on and "MarkupPickerThumb" or "MarkupPickerScrollbar"),
		})
	end
	return m.block({ width = 1, shrink = 0, lines })
end

--- `fn` kept in a signal, which tells what reads it only when its value
--- changes: a memo tells them whenever anything it read did.
---@generic T
---@param fn fun(): T
---@return fun(): T
local function settled(fn)
	local value = reactive.signal(nil)
	reactive.effect(function()
		value(fn())
	end)
	return value
end

--- What the list shows: the rows that fit, and a scrollbar when not all do.
---
--- A row stays mounted for as long as its item shows, so moving the selection
--- draws the two rows it moves between, and scrolling by one adds a row and
--- takes one away, rather than every row being made again.
function Picker:element()
	local m = require("markup")
	local render = self.opts.render or {}
	local row = render.row or M.row

	-- The rows that show, each the same table for as long as its item shows at
	-- the same place in the same matches: a row with nothing new draws nothing.
	local shown = {} ---@type table<any, { entry: markup.picker.entry, index: integer }>
	local visible = reactive.memo(function()
		local entries = self.filtered()
		local first = self.offset() + 1
		local list, now = {}, {}
		for index = first, math.min(first + self.rows() - 1, #entries) do
			local entry = entries[index]
			local key = entry.item
			local last = shown[key]
			local value = last and last.entry == entry and last.index == index and last
				or { entry = entry, index = index }
			now[key] = value
			list[#list + 1] = value
		end
		shown = now
		return list
	end)
	local bar = settled(function()
		return #self.filtered() > self.rows()
	end)
	local empty = settled(function()
		return #self.filtered() == 0
	end)

	local function Row(get)
		-- Its own answer, so only the rows whose answer changed draw again.
		local active = settled(function()
			return self.selected() == get().index
		end)
		return m.block({
			-- Clicking a row picks it.
			click = self.opts.click,
			on_press = function()
				self.selected(get().index)
				self:confirm()
			end,
			function()
				local value = get()
				return row(value.entry, {
					index = value.index,
					selected = active(),
					width = self.width() - (bar() and 1 or 0),
					picker = self,
				})
			end,
		})
	end

	return m.block(function()
		if empty() then
			if render.empty then
				return render.empty(self)
			end
			return m.block({
				padding = { 0, 2 },
				m.inline(self.opts.empty or "No matches", "MarkupPickerEmpty"),
			})
		end
		return m.flex({
			m.block({
				grow = 1,
				shrink = 1,
				min_width = 0,
				m.each(visible, Row, {
					key = function(value)
						return value.entry.item
					end,
				}),
			}),
			m.show(bar, function()
				return m.block(function()
					return self:scrollbar(#self.filtered(), self.rows())
				end)
			end),
		})
	end)
end

--- A count typed before a key, or `default` without one.
local function count(default)
	return vim.v.count > 0 and vim.v.count or default
end

--- Every key the picker answers, as `{ mode, lhs, action }` by mode and lhs,
--- for `kind` of window: the input, the list, or another that is part of it.
---@param kind "input"|"list"|"other"
function Picker:keys(kind)
	local function half()
		return math.max(math.floor(self.rows() / 2), 1)
	end
	local function down()
		self:move(count(1))
	end
	local function up()
		self:move(-count(1))
	end
	local function close()
		self:close()
	end

	--- The wheel scrolls the list by 'mousescroll' when it is over the picker,
	--- and does what it always does anywhere else.
	local function wheel(direction, key)
		return function()
			local over = vim.fn.getmousepos().winid
			if self.owned[over] then
				local step = tonumber(vim.o.mousescroll:match("ver:(%d+)")) or 3
				self:scroll(direction * step)
			else
				api.nvim_feedkeys(vim.keycode(key), "n", false)
			end
		end
	end

	local keys = {}
	local function add(modes, lhs, action)
		for _, mode in ipairs(type(modes) == "table" and modes or { modes }) do
			keys[mode .. " " .. lhs] = { mode, lhs, action }
		end
	end

	add({ "n", "i" }, "<ScrollWheelDown>", wheel(1, "<ScrollWheelDown>"))
	add({ "n", "i" }, "<ScrollWheelUp>", wheel(-1, "<ScrollWheelUp>"))
	add({ "n", "i" }, "<C-c>", close)
	add("n", "q", close)
	add("n", "<Esc>", close)

	if kind ~= "other" then
		local both = {
			["<CR>"] = function()
				self:confirm()
			end,
			["<Down>"] = down,
			["<Up>"] = up,
			["<C-j>"] = down,
			["<C-k>"] = up,
			["<C-n>"] = down,
			["<C-p>"] = up,
			["<Tab>"] = down,
			["<S-Tab>"] = up,
			["<C-d>"] = function()
				self:page(count(half()))
			end,
			["<C-u>"] = function()
				self:page(-count(half()))
			end,
			["<PageDown>"] = function()
				self:page(self.rows())
			end,
			["<PageUp>"] = function()
				self:page(-self.rows())
			end,
		}
		for lhs, action in pairs(both) do
			add({ "n", "i" }, lhs, action)
		end

		local normal = {
			j = down,
			k = up,
			gg = function()
				self:select(count(1))
			end,
			G = function()
				self:select(vim.v.count > 0 and vim.v.count or #self.filtered())
			end,
			["<C-f>"] = function()
				self:page(self.rows() * count(1))
			end,
			["<C-b>"] = function()
				self:page(-self.rows() * count(1))
			end,
			["<C-e>"] = function()
				self:scroll(count(1))
			end,
			["<C-y>"] = function()
				self:scroll(-count(1))
			end,
			H = function()
				self:select(self.offset() + count(1))
			end,
			M = function()
				local shown = math.min(self.rows(), #self.filtered() - self.offset())
				self:select(self.offset() + math.ceil(shown / 2))
			end,
			L = function()
				local last = math.min(self.offset() + self.rows(), #self.filtered())
				self:select(last - count(1) + 1)
			end,
			zz = function()
				self:align("middle")
			end,
			zt = function()
				self:align("top")
			end,
			zb = function()
				self:align("bottom")
			end,
		}
		for lhs, action in pairs(normal) do
			add("n", lhs, action)
		end
	end

	if kind == "input" then
		add("i", "<Esc>", self.opts.esc == "close" and close or function()
			vim.cmd.stopinsert()
		end)
		add("n", "/", function()
			self:focus_list()
		end)
	else
		-- Back to typing, as these start insert mode anywhere else.
		for _, lhs in ipairs({ "i", "a", "I", "A", "/" }) do
			add("n", lhs, function()
				self:focus_input()
			end)
		end
	end

	for lhs, key in pairs(self.opts.keys or {}) do
		if key == false then
			for _, mode in ipairs({ "n", "i" }) do
				keys[mode .. " " .. lhs] = nil
			end
		else
			local action = type(key) == "function" and key or key[1]
			local modes = type(key) == "table" and key.mode or "n"
			add(modes, lhs, function()
				action(self)
			end)
		end
	end
	return keys
end

--- Puts the picker's keys on `buf`, for `kind` of window.
---@param buf integer
---@param kind "input"|"list"|"other"
function Picker:bind(buf, kind)
	for _, key in pairs(self:keys(kind)) do
		vim.keymap.set(key[1], key[2], key[3], { buffer = buf, nowait = true })
	end
end

--- Types into `buf`, shown in `win`: the query follows its first line.
---@param buf integer
---@param win? integer
function Picker:attach_input(buf, win)
	self.input_buf, self.input_win = buf, win
	self.typed = api.nvim_buf_get_lines(buf, 0, 1, false)[1] or ""
	self:own(win)
	self:bind(buf, "input")

	api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
		group = self.group,
		buffer = buf,
		callback = function()
			self:sync()
			reactive.flush()
		end,
	})

	-- Typing can end without <Esc>, as with a plugin that maps jk to it and
	-- sends it unmapped: what <Esc> does, ending typing does too.
	api.nvim_create_autocmd("InsertLeave", {
		group = self.group,
		buffer = buf,
		callback = function()
			if self.closed or self.leaving_input then
				return
			end
			if self.opts.on_input_leave then
				vim.schedule(function()
					if not self.closed then
						self.opts.on_input_leave(self)
					end
				end)
			elseif self.opts.esc == "close" then
				vim.schedule(function()
					self:close()
				end)
			end
		end,
	})

	-- Clicking the list takes the focus there for a moment: the input gets it
	-- back in the mode it had.
	api.nvim_create_autocmd("WinLeave", {
		group = self.group,
		buffer = buf,
		callback = function()
			self.typing = vim.fn.mode() == "i"
		end,
	})
end

--- Lets go of the input, for one that only shows while typing.
function Picker:detach_input()
	if self.input_win then
		self.owned[self.input_win] = nil
	end
	self.input_buf, self.input_win = nil, nil
end

--- Draws the list into `win`, a `markup.window`.
---@param win markup.window
function Picker:attach_list(win)
	self.list = win
	self:own(win.win)
	-- The list shows where the selection is by itself, so its cursor is hidden.
	self.view = Markup.view(win, { hide_cursor = true })
	self.view:on_commit(function()
		self:place_cursor()
	end)
	self:bind(win.buf, "list")
	self:measure()
	-- Made in the picker's scope, so what the list computes stops with it.
	local element = reactive.scope(function()
		return self:element()
	end, self.owner)
	self.view:render(element)

	api.nvim_create_autocmd("CursorMoved", {
		group = self.group,
		buffer = win.buf,
		callback = function()
			self:follow_cursor()
		end,
	})

	-- It holds only the rows that show, so it must never scroll itself.
	api.nvim_create_autocmd("WinScrolled", {
		group = self.group,
		callback = function()
			if win:win_valid() then
				api.nvim_win_call(win.win, function()
					if vim.fn.line("w0") ~= 1 then
						vim.fn.winrestview({ topline = 1 })
					end
				end)
			end
		end,
	})
	-- Measured again as it resizes, as often as a view lays out again for it.
	local measure, stop_measure = require("markup.util").throttle(function()
		if not self.closed then
			self:measure()
			reactive.flush()
		end
	end, require("markup.view").RESIZE_MS)
	self:on_cleanup(stop_measure)
	api.nvim_create_autocmd({ "WinResized", "VimResized" }, {
		group = self.group,
		callback = function()
			vim.schedule(measure)
		end,
	})
end

--- A picker that draws into windows it is given, with `attach_input` and
--- `attach_list`, and `own` for any others that belong to it. `Markup.picker`
--- makes the windows for you.
---@param opts markup.picker.core_opts
---@return markup.picker.instance
function M.new(opts)
	define_groups()
	local self = setmetatable({
		opts = opts,
		closed = false,
		owned = {},
		cleanups = {},
		in_list = false,
		origin = api.nvim_get_current_win(),
	}, Picker)
	-- `picker.close()` as well as `picker:close()`.
	self.close = function()
		Picker.close(self)
	end
	self.query = reactive.signal("")
	self.selected = reactive.signal(1)
	self.offset = reactive.signal(0)
	self.rows = reactive.signal(15)
	self.width = reactive.signal(80)
	self.group = api.nvim_create_augroup("markup_picker_" .. tostring(self):gsub("table: ", ""), {
		clear = true,
	})

	-- The engine's matcher unless the caller matches, or the engine has none.
	self.uses_native = not opts.filter and native ~= nil and native.create_matcher ~= nil
	self.found = reactive.signal(nil)

	-- Owns what the picker computes, so closing it stops all of that.
	self.filtered, self.owner = reactive.scope(function()
		return reactive.memo(function()
			if self.uses_native then
				self.query()
				return self:native_entries()
			end
			return (opts.filter or M.filter)(self:items(), self.query())
		end)
	end)
	reactive.scope(function()
		-- A query set from code, rather than typed, is matched too.
		reactive.effect(function()
			local query = self.query()
			reactive.untrack(function()
				self:search(query)
			end)
		end)
	end, self.owner)
	self.seen = reactive.untrack(self.filtered)
	reactive.scope(function()
		-- Matches that change for anything but the query, such as a filter the
		-- caller has, start from the top as well.
		reactive.effect(function()
			local filtered = self.filtered()
			if filtered ~= self.seen then
				reactive.untrack(function()
					self:to_top()
				end)
			end
		end)
	end, self.owner)

	-- Moving to a window that is not the picker's ends it. The list has the
	-- focus for a moment when it is clicked, and gives it back to the input.
	api.nvim_create_autocmd("WinEnter", {
		group = self.group,
		callback = function()
			vim.schedule(function()
				if self.closed then
					return
				end
				local current = api.nvim_get_current_win()
				if not self.owned[current] then
					if self.opts.auto_close ~= false then
						self:close()
					end
					return
				end
				local list = self.list
				if
					list
					and current == list.win
					and not self.in_list
					and self.input_win
					and api.nvim_win_is_valid(self.input_win)
				then
					api.nvim_set_current_win(self.input_win)
					if self.typing then
						vim.cmd.startinsert({ bang = true })
					else
						vim.cmd.stopinsert()
					end
				end
			end)
		end,
	})
	return self
end

--- Resolves a size: cells as they are, a fraction of `total` otherwise.
local function size(value, total)
	return value <= 1 and math.floor(total * value) or math.floor(value)
end

--- The prompt and the list in a float, in the middle of the editor.
---@param picker markup.picker.instance
---@param opts markup.picker.opts
local function float_layout(picker, opts)
	local function geometry()
		local width = math.min(size(opts.width or 80, vim.o.columns), vim.o.columns - 4)
		local height = math.max(math.min(size(opts.height or 15, vim.o.lines), vim.o.lines - 9), 1)
		-- The prompt under its border, the line between, the list and its border.
		local top = math.max(math.floor((vim.o.lines - (height + 4)) / 2) - 1, 0)
		local left = math.floor((vim.o.columns - width - 2) / 2)
		return width, height, top, left
	end
	local width, height, top, left = geometry()

	local prompt_buf = api.nvim_create_buf(false, true)
	vim.bo[prompt_buf].bufhidden = "wipe"
	local prompt_win = api.nvim_open_win(prompt_buf, true, {
		relative = "editor",
		row = top,
		col = left,
		width = width,
		height = 1,
		-- One panel with the list: the list draws the line between them.
		border = { "╭", "─", "╮", "│", "", "", "", "│" },
		title = opts.title and (" %s "):format(opts.title) or nil,
		title_pos = opts.title and "center" or nil,
		style = "minimal",
		zindex = 60,
	})

	local list = Markup.window({
		position = "float",
		relative = "editor",
		row = top + 2,
		col = left,
		width = width,
		height = height,
		border = { "├", "─", "┤", "│", "╯", "─", "╰", "│" },
		enter = false,
		-- Clicks pass through windows that cannot have the focus.
		focusable = true,
		minimal = true,
		backdrop = false,
		zindex = 60,
	})

	picker:on_cleanup(function()
		list:close()
		if api.nvim_win_is_valid(prompt_win) then
			api.nvim_win_close(prompt_win, true)
		end
	end)

	-- Placed again for the editor's new size.
	api.nvim_create_autocmd("VimResized", {
		group = picker.group,
		callback = function()
			if picker.closed then
				return
			end
			local new_width, new_height, new_top, new_left = geometry()
			if api.nvim_win_is_valid(prompt_win) then
				api.nvim_win_set_config(prompt_win, {
					relative = "editor",
					row = new_top,
					col = new_left,
					width = new_width,
				})
			end
			if list:win_valid() then
				api.nvim_win_set_config(list.win, {
					relative = "editor",
					row = new_top + 2,
					col = new_left,
					width = new_width,
					height = new_height,
				})
			end
			picker:measure()
			reactive.flush()
		end,
	})

	return prompt_buf, prompt_win, list
end

--- The prompt and the list in a column or a row along an edge of the editor.
---@param picker markup.picker.instance
---@param opts markup.picker.opts
local function edge_layout(picker, opts)
	local side = opts.layout
	local across = side == "left" or side == "right"
	local prompt = Markup.window({ show = false, minimal = true, enter = false })
	local list = Markup.window({ show = false, minimal = true, enter = false })
	local layout = Markup.layout({
		wins = { prompt = prompt, list = list },
		show = false,
		layout = {
			box = "vertical",
			position = side,
			width = across and (opts.width or 0.4) or 0,
			height = across and 0 or (opts.height or 0.4),
			border = "rounded",
			title = opts.title and (" %s "):format(opts.title) or nil,
			title_pos = "center",
			{ win = "prompt", height = 1, border = "bottom" },
			{ win = "list" },
		},
	})
	layout:show()
	vim.bo[prompt.buf].bufhidden = "wipe"
	picker:own(layout.root.win)
	picker:on_cleanup(function()
		layout:close()
	end)
	api.nvim_set_current_win(prompt.win)
	return prompt.buf, prompt.win, list
end

---@param opts markup.picker.opts
---@return markup.picker.instance
function M.open(opts)
	local picker = M.new(opts)
	if type(opts.layout) == "function" then
		opts.layout(picker)
		return picker
	end

	local prompt_buf, prompt_win, list
	if opts.layout and opts.layout ~= "float" then
		prompt_buf, prompt_win, list = edge_layout(picker, opts)
	else
		prompt_buf, prompt_win, list = float_layout(picker, opts)
	end
	picker:attach_input(prompt_buf, prompt_win)
	picker:attach_list(list)

	local ns = api.nvim_create_namespace("markup_picker")
	api.nvim_buf_set_extmark(prompt_buf, ns, 0, 0, {
		virt_text = { { opts.prompt or "> ", "MarkupPickerPrompt" } },
		virt_text_pos = "inline",
		right_gravity = false,
	})

	if opts.count ~= false then
		local mark
		reactive.scope(function()
			reactive.effect(function()
				local text = ("%d/%d"):format(#picker.filtered(), #picker:items())
				if not api.nvim_buf_is_valid(prompt_buf) then
					return
				end
				-- Out of the way of a query that reaches it: the query matters more.
				local typed = vim.fn.strdisplaywidth(picker.query())
				local room = api.nvim_win_is_valid(prompt_win)
						and api.nvim_win_get_width(prompt_win)
					or picker.width()
				if typed + 2 + #text + 1 > room then
					if mark then
						api.nvim_buf_del_extmark(prompt_buf, ns, mark)
						mark = nil
					end
					return
				end
				mark = api.nvim_buf_set_extmark(prompt_buf, ns, 0, 0, {
					id = mark,
					virt_text = { { text, "MarkupPickerCount" } },
					virt_text_pos = "right_align",
				})
			end)
		end, picker.owner)
	end

	reactive.flush()
	vim.cmd.startinsert()
	return picker
end

return setmetatable(M, {
	__call = function(_, opts)
		return M.open(opts)
	end,
})
