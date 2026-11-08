--- A popup that narrows a list as you type and picks one item.
---
--- A prompt float sits on top of a list float. Matching is Neovim's own fuzzy
--- matching, so it is fast enough for thousands of items, and only the rows that
--- fit the list are ever mounted.

local reactive = require("markup.reactive")

local api = vim.api

---@class markup.picker.span
---@field [1] string text
---@field [2]? string highlight

---@class markup.picker.item
---@field label string what is shown and matched, with matches highlighted
---@field keywords? string matched as well, but never shown, such as an id
---@field prefix? markup.picker.span[] before the label
---@field suffix? markup.picker.span[] at the end of the row
---@field value any

---@class markup.picker.opts
---@field items markup.picker.item[]
---@field on_select fun(value: any, item: markup.picker.item)
---@field title? string
---@field width? integer 80 by default
---@field height? integer rows of the list, 15 by default
---@field empty? string shown when nothing matches
---@field click? "single"|"double"|false which click picks a row, single by default

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

---@param opts markup.picker.opts
---@return { close: function }
function M.open(opts)
	local m = require("markup")
	define_groups()

	local items = opts.items
	local width = math.min(opts.width or 80, vim.o.columns - 4)
	local height = math.max(math.min(opts.height or 15, vim.o.lines - 9), 1)
	-- The prompt under its border, the line between, the list and its border.
	local top = math.max(math.floor((vim.o.lines - (height + 4)) / 2) - 1, 0)
	local left = math.floor((vim.o.columns - width - 2) / 2)

	local origin = api.nvim_get_current_win()
	local query = reactive.signal("")
	local selected = reactive.signal(1)
	local offset = reactive.signal(0)

	-- Owns what the picker computes, so closing it stops all of that.
	local filtered, owner = reactive.scope(function()
		return reactive.memo(function()
			return M.filter(items, query())
		end)
	end)

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
	local view = Markup.view(list)

	local ns = api.nvim_create_namespace("markup_picker")
	local count_mark

	local closed = false
	local function close()
		if closed then
			return
		end
		closed = true

		vim.cmd.stopinsert()
		reactive.dispose(owner)
		view:destroy()
		list:close()
		if api.nvim_win_is_valid(prompt_win) then
			api.nvim_win_close(prompt_win, true)
		end
		if api.nvim_win_is_valid(origin) then
			api.nvim_set_current_win(origin)
		end
	end

	--- Neovim holds back TextChangedI while keys are still queued, as when typing
	--- fast or pasting, so whatever acts on the query reads it first.
	local function sync()
		local text = api.nvim_buf_is_valid(prompt_buf) and api.nvim_buf_get_lines(prompt_buf, 0, 1, false)[1] or ""
		if text ~= reactive.untrack(query) then
			query(text)
			selected(1)
			offset(0)
		end
	end

	local function move(by)
		sync()
		local count = #filtered()
		if count == 0 then
			return
		end

		local index = math.max(math.min(selected() + by, count), 1)
		selected(index)
		if index <= offset() then
			offset(index - 1)
		elseif index > offset() + height then
			offset(index - height)
		end
		reactive.flush()
	end

	local function confirm()
		sync()
		local entry = filtered()[selected()]
		close()
		if entry then
			opts.on_select(entry.item.value, entry.item)
		end
	end

	local function Row(entry, index)
		local item = entry.item
		local active = index == selected()
		local spans = {}
		for _, span in ipairs(item.prefix or {}) do
			spans[#spans + 1] = m.inline(span[1], span[2])
		end
		for _, span in ipairs(M.highlight(item.label, entry.positions)) do
			spans[#spans + 1] = m.inline(span[1], span[2])
		end

		return m.flex({
			-- Clicking a row picks it.
			click = opts.click,
			on_press = function()
				selected(index)
				confirm()
			end,
			white_space = "nowrap",
			justify = "between",
			style = active and "MarkupPickerSelected" or nil,
			m.inline({
				shrink = 1,
				-- Cut where it no longer fits, rather than run under the suffix.
				overflow_x = "hidden",
				m.inline(active and "▌" or " ", "MarkupPickerMarker"),
				m.inline({ margin_left = 1, spans }),
			}),
			item.suffix and m.inline({
				shrink = 0,
				margin_left = 1,
				margin_right = 1,
				vim.tbl_map(function(span)
					return m.inline(span[1], span[2])
				end, item.suffix),
			}),
		})
	end

	view:render(m.block(function()
		local entries = filtered()
		if #entries == 0 then
			return m.block({ padding = { 0, 2 }, m.inline(opts.empty or "No matches", "MarkupPickerEmpty") })
		end

		local rows = {}
		local first = offset() + 1
		for index = first, math.min(first + height - 1, #entries) do
			rows[#rows + 1] = Row(entries[index], index)
		end
		return rows
	end))

	reactive.scope(function()
		reactive.effect(function()
			local text = ("%d/%d"):format(#filtered(), #items)
			if api.nvim_buf_is_valid(prompt_buf) then
				count_mark = api.nvim_buf_set_extmark(prompt_buf, ns, 0, 0, {
					id = count_mark,
					virt_text = { { text, "MarkupPickerCount" } },
					virt_text_pos = "right_align",
				})
			end
		end)
	end, owner)

	api.nvim_buf_set_extmark(prompt_buf, ns, 0, 0, {
		virt_text = { { "> ", "MarkupPickerPrompt" } },
		virt_text_pos = "inline",
		right_gravity = false,
	})

	api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
		buffer = prompt_buf,
		callback = function()
			sync()
			reactive.flush()
		end,
	})

	-- Leaving the prompt ends the picker, unless it was for the list, such as
	-- with a click, which then picks what it hit.
	api.nvim_create_autocmd("WinLeave", {
		buffer = prompt_buf,
		callback = function()
			vim.schedule(function()
				if closed then
					return
				end
				if list:win_valid() and api.nvim_get_current_win() == list.win and api.nvim_win_is_valid(prompt_win) then
					api.nvim_set_current_win(prompt_win)
					vim.cmd.startinsert({ bang = true })
					return
				end
				close()
			end)
		end,
	})

	local keys = {
		["<CR>"] = confirm,
		["<Esc>"] = close,
		["<C-c>"] = close,
		["<Down>"] = function()
			move(1)
		end,
		["<Up>"] = function()
			move(-1)
		end,
		["<C-n>"] = function()
			move(1)
		end,
		["<C-p>"] = function()
			move(-1)
		end,
		["<Tab>"] = function()
			move(1)
		end,
		["<S-Tab>"] = function()
			move(-1)
		end,
		["<C-d>"] = function()
			move(math.floor(height / 2))
		end,
		["<C-u>"] = function()
			move(-math.floor(height / 2))
		end,
	}
	for lhs, action in pairs(keys) do
		vim.keymap.set({ "i", "n" }, lhs, action, { buffer = prompt_buf, nowait = true })
	end
	for lhs, action in pairs({ q = close, j = keys["<Down>"], k = keys["<Up>"] }) do
		vim.keymap.set("n", lhs, action, { buffer = prompt_buf, nowait = true })
	end

	reactive.flush()
	vim.cmd.startinsert()

	return { close = close }
end

return setmetatable(M, {
	__call = function(_, opts)
		return M.open(opts)
	end,
})
