---@module 'mini.test'

local new_set = MiniTest.new_set
local eq = MiniTest.expect.equality
local child = MiniTest.new_child_neovim()
local Screen = dofile("tests/helpers/screen.lua")

local T = new_set({
	hooks = {
		pre_case = function()
			child.restart({ "-u", "scripts/minimal_init.lua" })
			child.o.lines, child.o.columns = 30, 100
			child.lua([[
				m = require("markup")
				reactive = require("markup.reactive")
				picked = nil
				function open(extra)
					local items = {}
					for i, name in ipairs({ "Two Sum", "Add Two Numbers", "Three Sum", "Reverse Integer" }) do
						items[i] = {
							label = name,
							keywords = tostring(i),
							prefix = { { i .. ". ", "Comment" } },
							suffix = { { "50%", "Comment" } },
							value = i,
						}
					end
					picker = Markup.picker(vim.tbl_extend("force", {
						title = "Pick",
						items = items,
						on_select = function(value) picked = value end,
					}, extra or {}))
					reactive.flush()
				end
				function list_lines()
					for _, win in ipairs(vim.api.nvim_list_wins()) do
						local buf = vim.api.nvim_win_get_buf(win)
						-- The list, which is taller than the prompt, focused or not.
						local config = vim.api.nvim_win_get_config(win)
						if config.relative ~= "" and config.height > 1 then
							return vim.tbl_map(function(line)
								return (line:gsub("%s+$", ""))
							end, vim.api.nvim_buf_get_lines(buf, 0, -1, false))
						end
					end
				end
				--- A picker of `count` items, "item 01" and on, `height` rows tall.
				function open_many(count, height, extra)
					local items = {}
					for i = 1, count do
						items[i] = { label = ("item %02d"):format(i), value = i }
					end
					picker = Markup.picker(vim.tbl_extend("force", {
						items = items,
						height = height,
						width = 40,
						on_select = function(value) picked = value end,
					}, extra or {}))
					reactive.flush()
				end
				--- The label of the row that is selected, and the first one that shows.
				function selection()
					local lines = list_lines()
					local at
					for _, line in ipairs(lines) do
						if line:find("▌", 1, true) then at = line:match("item %d+") end
					end
					return { selected = at, top = lines[1]:match("item %d+") }
				end
				function floats()
					return #vim.tbl_filter(function(win)
						return vim.api.nvim_win_get_config(win).relative ~= ""
					end, vim.api.nvim_list_wins())
				end
			]])
		end,
		post_once = function()
			child.stop()
		end,
	},
})

local function type(keys)
	child.type_keys(keys)
	child.lua("reactive.flush()")
end

T["opens a prompt over a list"] = function()
	child.lua("open()")
	eq(child.lua_get("floats()"), 2)
	eq(child.fn.mode(), "i")
	eq(#child.lua_get("list_lines()"), 4)
end

T["the list sits right below the prompt"] = function()
	child.lua([[
		open()
		prompt = vim.api.nvim_get_current_win()
		for _, win in ipairs(vim.api.nvim_list_wins()) do
			if win ~= prompt and vim.api.nvim_win_get_config(win).relative ~= "" then list = win end
		end
	]])
	-- One panel: the prompt, then the line between them.
	eq(child.lua_get("vim.fn.win_screenpos(list)[1] - vim.fn.win_screenpos(prompt)[1]"), 2)
	eq(child.lua_get("vim.api.nvim_win_get_config(list).border[1]"), "├")
	eq(child.lua_get("vim.fn.win_screenpos(list)[2] == vim.fn.win_screenpos(prompt)[2]"), true)
end

T["filters as you type"] = function()
	child.lua("open()")
	type("sum")
	local lines = child.lua_get("list_lines()")
	eq(#lines, 2)
	eq(lines[1]:find("Sum", 1, true) ~= nil, true)
end

T["matches hidden keywords"] = function()
	child.lua("open()")
	type("4")
	local lines = child.lua_get("list_lines()")
	eq(#lines, 1)
	eq(lines[1]:find("Reverse Integer", 1, true) ~= nil, true)
end

T["highlights what matched"] = function()
	child.lua("open()")
	type("tw")
	child.lua([[
		matched = {}
		for _, view in pairs(vim.tbl_keys(Markup.views)) do
			local buf = view.win.buf
			if buf and vim.api.nvim_buf_is_valid(buf) then
				for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(buf, view.ns, 0, -1, { details = true })) do
					if mark[4].hl_group == "MarkupPickerMatch" then
						matched[#matched + 1] = vim.api.nvim_buf_get_text(buf, mark[2], mark[3], mark[2], mark[4].end_col, {})[1]
					end
				end
			end
		end
	]])
	eq(child.lua_get("table.concat(matched)"):lower():find("tw", 1, true) ~= nil, true)
end

T["shows a count"] = function()
	child.lua("open()")
	type("sum")
	child.lua([[
		local marks = vim.api.nvim_buf_get_extmarks(0, -1, 0, -1, { details = true })
		texts = {}
		for _, mark in ipairs(marks) do
			for _, chunk in ipairs(mark[4].virt_text or {}) do texts[#texts + 1] = chunk[1] end
		end
	]])
	eq(vim.tbl_contains(child.lua_get("texts"), "2/4"), true)
end

T["moves and picks"] = function()
	child.lua("open()")
	type("<C-n><C-n>")
	type("<CR>")
	eq(child.lua_get("picked"), 3)
	eq(child.lua_get("floats()"), 0)
	eq(child.fn.mode(), "n")
end

T["a step off either end goes round to the other"] = function()
	child.lua("open()")
	type("<C-p>")
	type("<CR>")
	eq(child.lua_get("picked"), 4)

	child.lua("open()")
	type("<Down><Down><Down><Down><CR>")
	eq(child.lua_get("picked"), 1)
end

T["picks the best match"] = function()
	child.lua("open()")
	type("reverse<CR>")
	eq(child.lua_get("picked"), 4)
end

T["moving right after typing uses the new query"] = function()
	child.lua("open()")
	type("sum<C-n><CR>")
	eq(child.lua_get("picked"), 3)
end

T["closes without picking"] = function()
	child.lua("open()")
	-- Out of typing, then out of the picker.
	type("<Esc>")
	eq(child.lua_get("floats()"), 2)
	eq(child.fn.mode(), "n")
	type("<Esc>")
	eq(child.lua_get("floats()"), 0)
	eq(child.lua_get("picked"), vim.NIL)

	child.lua("open()")
	type("<C-c>")
	eq(child.lua_get("floats()"), 0)

	child.lua("open()")
	type("<Esc>q")
	eq(child.lua_get("floats()"), 0)
end

T["esc = close closes while typing"] = function()
	child.lua([[open({ esc = "close" })]])
	type("<Esc>")
	eq(child.lua_get("floats()"), 0)
end

T["closes when focus leaves"] = function()
	child.lua([[
		origin = vim.api.nvim_get_current_win()
		open()
		vim.api.nvim_set_current_win(origin)
	]])
	child.lua("vim.wait(20, function() return false end)")
	eq(child.lua_get("floats()"), 0)
end

T["says when nothing matches"] = function()
	child.lua("open()")
	type("zzzz")
	eq(child.lua_get("list_lines()")[1]:find("No matches", 1, true) ~= nil, true)
	type("<CR>")
	eq(child.lua_get("picked"), vim.NIL)
end

T["scrolls to keep the selection in view"] = function()
	child.lua([[
		local many = {}
		for i = 1, 50 do many[i] = { label = "item " .. i, value = i } end
		open({ items = many, height = 5 })
	]])
	for _ = 1, 7 do
		type("<C-n>")
	end
	local lines = child.lua_get("list_lines()")
	eq(#lines, 5)
	eq(lines[5]:find("item 8", 1, true) ~= nil, true)
	type("<CR>")
	eq(child.lua_get("picked"), 8)
end

T["returns to the window it came from"] = function()
	child.lua([[
		vim.cmd("vnew")
		origin = vim.api.nvim_get_current_win()
		open()
	]])
	type("<C-c>")
	eq(child.lua_get("vim.api.nvim_get_current_win() == origin"), true)
end

T["handles thousands of items"] = function()
	child.lua([[
		local many = {}
		for i = 1, 5000 do many[i] = { label = "problem number " .. i, keywords = "slug-" .. i, value = i } end
		open({ items = many })
		local started = vim.uv.hrtime()
		vim.api.nvim_buf_set_lines(0, 0, -1, false, { "number 4999" })
		vim.api.nvim_exec_autocmds("TextChangedI", { buffer = 0 })
		elapsed = (vim.uv.hrtime() - started) / 1e6
	]])
	eq(child.lua_get("elapsed < 200"), true)
	eq(child.lua_get("list_lines()")[1]:find("4999", 1, true) ~= nil, true)
end

T["a label too long is cut before the suffix"] = function()
	child.o.columns = 40
	child.lua([[
		local items = {}
		for i = 1, 3 do
			items[i] = {
				label = "Longest Substring Without Repeating Characters",
				prefix = { { i .. ". " } },
				suffix = { { "58.1%" } },
				value = i,
			}
		end
		Markup.picker({ title = "Pick", items = items, on_select = function() end })
		reactive.flush()
	]])
	for _, line in ipairs(child.lua_get("list_lines()")) do
		if line ~= "" then
			-- The suffix ends the row, and nothing of the label runs past it.
			eq(line:match("58%.1%%$") ~= nil, true)
			eq(select(2, line:gsub("58%.1%%", "")), 1)
			eq(line:find("Characters", 1, true), nil)
		end
	end
end

T["normal mode"] = new_set()

T["normal mode"]["moves by a count, going round past the ends"] = function()
	child.lua("open_many(40, 8)")
	type("<Esc>3j")
	eq(child.lua_get("selection().selected"), "item 04")
	type("2k")
	eq(child.lua_get("selection().selected"), "item 02")
	-- As the Snacks picker does: past the end, round to the start, counts too.
	type("99j")
	eq(child.lua_get("selection()"), { selected = "item 21", top = "item 14" })
	type("ggk")
	eq(child.lua_get("selection()"), { selected = "item 40", top = "item 33" })
	type("j")
	eq(child.lua_get("selection()"), { selected = "item 01", top = "item 01" })
end

T["normal mode"]["j and k move, whatever they are mapped to elsewhere"] = function()
	child.lua([[
		-- As many configs have them.
		vim.keymap.set("n", "j", "v:count == 0 ? 'gj' : 'j'", { expr = true })
		vim.keymap.set("n", "k", "v:count == 0 ? 'gk' : 'k'", { expr = true })
		open_many(40, 8)
	]])
	type("<Esc>jj")
	eq(child.lua_get("selection().selected"), "item 03")
	type("k")
	eq(child.lua_get("selection().selected"), "item 02")
	type("5j")
	eq(child.lua_get("selection().selected"), "item 07")
end

T["normal mode"]["/ takes the focus to the list, and i brings it back"] = function()
	child.lua("open_many(40, 8)")
	child.lua("prompt = vim.api.nvim_get_current_win()")
	type("<Esc>/")
	child.lua("vim.wait(20, function() return false end, 5)")
	eq(child.lua_get("vim.api.nvim_get_current_win() ~= prompt"), true)
	eq(child.lua_get("floats()"), 2)
	eq(child.fn.mode(), "n")

	-- The same keys, and the cursor stays on the selection.
	type("3j")
	eq(child.lua_get("selection().selected"), "item 04")
	eq(child.api.nvim_win_get_cursor(0)[1], 4)
	type("G")
	eq(child.lua_get("selection()"), { selected = "item 40", top = "item 33" })
	eq(child.api.nvim_win_get_cursor(0)[1], 8)

	type("i")
	child.lua("vim.wait(20, function() return false end, 5)")
	eq(child.lua_get("vim.api.nvim_get_current_win() == prompt"), true)
	eq(child.fn.mode(), "i")
	eq(child.lua_get("selection().selected"), "item 40")

	-- Picked from the list too.
	type("<Esc>/<CR>")
	eq(child.lua_get("picked"), 40)
end

T["normal mode"]["in the list, the selection follows its cursor"] = function()
	child.lua("open_many(40, 8)")
	type("<Esc>/")
	child.lua("vim.wait(20, function() return false end, 5)")
	-- As a click or a motion of Vim's own would move it.
	child.lua(
		"vim.api.nvim_win_set_cursor(0, { 5, 0 }); vim.api.nvim_exec_autocmds('CursorMoved', { buffer = 0 })"
	)
	eq(child.lua_get("selection().selected"), "item 05")
	child.lua("vim.api.nvim_win_set_cursor(0, { 3, 0 })")
	type("<CR>")
	eq(child.lua_get("picked"), 3)
end

T["normal mode"]["leaving the list for another window closes the picker"] = function()
	child.lua([[
		origin = vim.api.nvim_get_current_win()
		open_many(40, 8)
	]])
	type("<Esc>/")
	child.lua("vim.api.nvim_set_current_win(origin); vim.wait(20, function() return false end, 5)")
	eq(child.lua_get("floats()"), 0)
end

T["normal mode"]["gg and G go to a row, the first and last without a count"] = function()
	child.lua("open_many(40, 8)")
	type("<Esc>G")
	eq(child.lua_get("selection().selected"), "item 40")
	type("gg")
	eq(child.lua_get("selection().selected"), "item 01")
	type("17G")
	eq(child.lua_get("selection().selected"), "item 17")
	type("5gg")
	eq(child.lua_get("selection().selected"), "item 05")
	type("<CR>")
	eq(child.lua_get("picked"), 5)
end

T["normal mode"]["pages move the list and the selection together"] = function()
	child.lua("open_many(40, 8)")
	type("<Esc><C-d>")
	eq(child.lua_get("selection()"), { selected = "item 05", top = "item 05" })
	type("<C-u>")
	eq(child.lua_get("selection()"), { selected = "item 01", top = "item 01" })
	type("<C-f>")
	eq(child.lua_get("selection()"), { selected = "item 09", top = "item 09" })
	type("<C-b>")
	eq(child.lua_get("selection()"), { selected = "item 01", top = "item 01" })
	type("2<C-f>")
	eq(child.lua_get("selection()"), { selected = "item 17", top = "item 17" })
end

T["normal mode"]["C-e and C-y scroll, and the selection stays in view"] = function()
	child.lua("open_many(40, 8)")
	type("<Esc>3<C-e>")
	-- Row 1 scrolled out, so the selection is the first that shows.
	eq(child.lua_get("selection()"), { selected = "item 04", top = "item 04" })
	type("<C-y>")
	eq(child.lua_get("selection()"), { selected = "item 04", top = "item 03" })
	type("<C-e><C-e>")
	eq(child.lua_get("selection()"), { selected = "item 05", top = "item 05" })
end

T["normal mode"]["H, M and L select what shows, zz, zt and zb move the list"] = function()
	child.lua("open_many(40, 8)")
	type("<Esc>L")
	eq(child.lua_get("selection().selected"), "item 08")
	type("M")
	eq(child.lua_get("selection().selected"), "item 04")
	type("H")
	eq(child.lua_get("selection().selected"), "item 01")
	type("2L")
	eq(child.lua_get("selection().selected"), "item 07")

	type("20Gzt")
	eq(child.lua_get("selection()"), { selected = "item 20", top = "item 20" })
	type("zb")
	eq(child.lua_get("selection()"), { selected = "item 20", top = "item 13" })
	-- As in a buffer: as many rows above it as fit, with the odd one below.
	type("zz")
	eq(child.lua_get("selection()"), { selected = "item 20", top = "item 17" })
end

T["normal mode"]["i goes back to typing"] = function()
	child.lua("open_many(40, 8)")
	type("<Esc>")
	eq(child.fn.mode(), "n")
	type("i15")
	eq(child.fn.mode(), "i")
	eq(child.lua_get("selection().selected"), "item 15")
end

T["insert mode"] = new_set()

T["insert mode"]["C-w edits the query, C-d and C-u scroll"] = function()
	child.lua("open_many(40, 8)")
	type("item 1")
	type("<C-w>")
	eq(child.api.nvim_get_current_line(), "item ")
	type("<C-w>")
	eq(child.api.nvim_get_current_line(), "")

	type("<C-d>")
	eq(child.lua_get("selection()"), { selected = "item 05", top = "item 05" })
	type("<C-u>")
	eq(child.lua_get("selection()"), { selected = "item 01", top = "item 01" })
	eq(child.fn.mode(), "i")
end

T["insert mode"]["C-j and C-k move"] = function()
	child.lua("open_many(40, 8)")
	type("<C-j><C-j>")
	eq(child.lua_get("selection().selected"), "item 03")
	type("<C-k>")
	eq(child.lua_get("selection().selected"), "item 02")
end

T["insert mode"]["the selection keeps scrolloff rows from the edges"] = function()
	child.lua("vim.o.scrolloff = 2; open_many(40, 8)")
	type("<C-j><C-j><C-j><C-j><C-j>")
	-- Row 6 of 8 shows two rows below it: nothing has scrolled yet.
	eq(child.lua_get("selection()"), { selected = "item 06", top = "item 01" })
	type("<C-j>")
	eq(child.lua_get("selection()"), { selected = "item 07", top = "item 02" })
	-- At the very end, the last row is reached all the same.
	type("<Esc>G")
	eq(child.lua_get("selection()"), { selected = "item 40", top = "item 33" })
end

T["insert mode"]["page keys move a page"] = function()
	child.lua("open_many(40, 8)")
	type("<PageDown>")
	eq(child.lua_get("selection()"), { selected = "item 09", top = "item 09" })
	type("<PageUp>")
	eq(child.lua_get("selection()"), { selected = "item 01", top = "item 01" })
	eq(child.fn.mode(), "i")
end

T["mouse"] = new_set()

--- A UI attached, so the mouse finds floats as a terminal's would.
local function with_screen(fn)
	local screen = Screen.attach(child)
	local ok, err = pcall(fn, screen)
	screen:detach()
	if not ok then
		error(err, 0)
	end
end

--- Where a cell of the list is on the screen, from zero.
local function list_cell(row, col)
	return child.lua_get(([[(function()
		for _, win in ipairs(vim.api.nvim_list_wins()) do
			local config = vim.api.nvim_win_get_config(win)
			if config.relative ~= "" and win ~= vim.api.nvim_get_current_win() then
				local at = vim.fn.screenpos(win, %d, %d)
				return { at.row - 1, at.col - 1 }
			end
		end
	end)()]]):format(row + 1, col + 1))
end

T["mouse"]["the wheel scrolls the list, and the list never scrolls itself"] = function()
	child.lua("open_many(40, 8)")
	with_screen(function()
		local at = list_cell(2, 4)
		child.api.nvim_input_mouse("wheel", "down", "", 0, at[1], at[2])
		child.lua("vim.wait(20, function() return false end, 5); reactive.flush()")
		eq(child.lua_get("selection()"), { selected = "item 04", top = "item 04" })
		eq(#child.lua_get("list_lines()"), 8)
		child.api.nvim_input_mouse("wheel", "up", "", 0, at[1], at[2])
		child.lua("vim.wait(20, function() return false end, 5); reactive.flush()")
		eq(child.lua_get("selection()"), { selected = "item 04", top = "item 01" })

		-- As far as 'mousescroll' says.
		child.o.mousescroll = "ver:5,hor:6"
		child.api.nvim_input_mouse("wheel", "down", "", 0, at[1], at[2])
		child.lua("vim.wait(20, function() return false end, 5); reactive.flush()")
		eq(child.lua_get("selection()"), { selected = "item 06", top = "item 06" })
	end)
	eq(child.fn.mode(), "i")
end

T["mouse"]["after a click on the list the prompt keeps its mode"] = function()
	child.lua([[open_many(40, 8, { click = false })]])
	type("<Esc>")
	with_screen(function()
		local at = list_cell(2, 4)
		child.api.nvim_input_mouse("left", "press", "", 0, at[1], at[2])
		child.api.nvim_input_mouse("left", "release", "", 0, at[1], at[2])
		child.lua("vim.wait(50, function() return false end, 5)")
	end)
	eq(child.lua_get("floats()"), 2)
	eq(child.lua_get("vim.bo.buftype"), "nofile")
	eq(child.fn.mode(), "n")
end

T["mouse"]["a click picks the row under it"] = function()
	child.lua("open_many(40, 8)")
	with_screen(function()
		local at = list_cell(2, 4)
		child.api.nvim_input_mouse("left", "press", "", 0, at[1], at[2])
		child.api.nvim_input_mouse("left", "release", "", 0, at[1], at[2])
		child.lua("vim.wait(50, function() return false end, 5)")
	end)
	eq(child.lua_get("picked"), 3)
end

T["display"] = new_set()

T["display"]["a scrollbar shows where the list is, when it does not all fit"] = function()
	child.lua("open_many(40, 8)")
	local function bar()
		return child.lua_get([[(function()
			for _, win in ipairs(vim.api.nvim_list_wins()) do
				if win ~= vim.api.nvim_get_current_win() and vim.api.nvim_win_get_config(win).relative ~= "" then
					local buf = vim.api.nvim_win_get_buf(win)
					local thumb = {}
					for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(buf, -1, 0, -1, { details = true })) do
						if mark[4].hl_group == "MarkupPickerThumb" then thumb[#thumb + 1] = mark[2] end
					end
					return thumb
				end
			end
		end)()]])
	end
	-- 8 of 40 show: a thumb of 2 rows, at the top.
	eq(bar(), { 0, 1 })
	type("<Esc>G")
	eq(bar(), { 6, 7 })

	-- Everything fits: no scrollbar.
	child.lua("picker.close(); open_many(4, 8)")
	eq(bar(), {})
end

T["display"]["a label that does not fit ends in an ellipsis"] = function()
	child.lua([[
		picker = Markup.picker({
			width = 30,
			items = { { label = ("long "):rep(20), value = 1, suffix = { { "50%" } } } },
			on_select = function() end,
		})
		reactive.flush()
	]])
	local line = child.lua_get("list_lines()[1]")
	eq(line:find("…", 1, true) ~= nil, true)
	eq(line:find("50%", 1, true) ~= nil, true)
	eq(vim.fn.strdisplaywidth(line) <= 30, true)
end

T["display"]["the count steps aside for a long query"] = function()
	child.lua("open_many(40, 8)")
	local function count_shown()
		return child.lua_get([[#vim.tbl_filter(function(mark)
			return mark[4].virt_text and mark[4].virt_text[1][2] == "MarkupPickerCount"
		end, vim.api.nvim_buf_get_extmarks(0, -1, 0, -1, { details = true })) > 0]])
	end
	eq(count_shown(), true)
	type(("x"):rep(36))
	eq(count_shown(), false)
	type("<C-w>")
	eq(count_shown(), true)
end

T["display"]["the picker is placed again when the editor resizes"] = function()
	child.lua("open_many(40, 8)")
	local function left()
		return child.lua_get("vim.api.nvim_win_get_config(0).col")
	end
	local before = left()
	child.o.columns = 60
	child.lua("vim.wait(20, function() return false end, 5); reactive.flush()")
	eq(left(), math.floor((60 - 40 - 2) / 2))
	eq(left() ~= before, true)
end

T["core"] = new_set()

T["core"]["rows and matching of the caller's own"] = function()
	child.lua([[
		hard = m.signal(false)
		local problems = {}
		for i = 1, 30 do
			problems[i] = { id = i, title = ("problem %02d"):format(i), hard = i % 3 == 0 }
		end
		seen = {}
		picker = Markup.picker({
			items = problems,
			height = 8,
			-- Words, and a filter of the caller's that is not in the query.
			filter = function(items, query)
				local entries = {}
				for _, problem in ipairs(items) do
					if (not hard() or problem.hard) and problem.title:find(query, 1, true) then
						entries[#entries + 1] = { item = problem }
					end
				end
				return entries
			end,
			render = {
				row = function(entry, ctx)
					seen[#seen + 1] = ctx.width
					return m.block({ (ctx.selected and "* " or "  ") .. entry.item.title })
				end,
			},
			on_select = function(value) picked = value end,
		})
		reactive.flush()
	]])
	eq(child.lua_get("list_lines()[1]"), "* problem 01")
	eq(child.lua_get("seen[1] > 0"), true)

	-- The caller's filter changes, and the list starts from the top again.
	type("<C-j><C-j>")
	child.lua("hard(true); reactive.flush()")
	eq(child.lua_get("list_lines()[1]"), "* problem 03")
	type("<CR>")
	-- An item without a value is what is picked.
	eq(child.lua_get("picked.id"), 3)
end

T["core"]["items can change while it is open"] = function()
	child.lua([[
		items = m.signal({ { label = "one", value = 1 } })
		picker = Markup.picker({ items = items, on_select = function(v) picked = v end })
		reactive.flush()
	]])
	eq(child.lua_get("#list_lines()"), 1)
	child.lua(
		[[items({ { label = "one", value = 1 }, { label = "two", value = 2 } }); reactive.flush()]]
	)
	eq(child.lua_get("list_lines()"), { "▌ one", "  two" })
	eq(
		child.lua_get(
			"vim.api.nvim_buf_get_extmarks(0, -1, 0, -1, { details = true })[2][4].virt_text[1][1]"
		),
		"2/2"
	)
end

T["core"]["keys can be added and taken away"] = function()
	child.lua([[
		open_many(40, 8, {
			keys = {
				x = function(p) p:select(10) end,
				["<C-x>"] = { function(p) p:select(20) end, mode = { "i", "n" } },
				G = false,
			},
		})
	]])
	type("<C-x>")
	eq(child.lua_get("selection().selected"), "item 20")
	type("<Esc>x")
	eq(child.lua_get("selection().selected"), "item 10")
	-- G is gone, so it does what it does in the prompt's buffer: nothing here.
	type("G")
	eq(child.lua_get("selection().selected"), "item 10")
end

T["core"]["on_close says when it closes without a pick"] = function()
	child.lua([[
		closed = 0
		open_many(4, 8, { on_close = function() closed = closed + 1 end })
	]])
	type("<C-c>")
	eq(child.lua_get("closed"), 1)
	child.lua([[open_many(4, 8, { on_close = function() closed = closed + 1 end })]])
	type("<CR>")
	eq(child.lua_get("closed"), 1)
	eq(child.lua_get("picked"), 1)
end

T["core"]["leaving insert mode without the Esc mapping"] = function()
	-- As better-escape.nvim does it: jk sends <Esc>, unmapped.
	child.lua([[
		vim.keymap.set("i", "jk", function()
			vim.api.nvim_feedkeys(vim.keycode("<Esc>"), "in", false)
		end)
	]])
	local function escape()
		child.type_keys("j", "k")
		child.lua("vim.wait(20, function() return false end, 5); reactive.flush()")
	end

	child.lua("open_many(40, 8)")
	escape()
	eq(child.fn.mode(), "n")
	type("j")
	eq(child.lua_get("selection().selected"), "item 02")

	child.lua([[open_many(40, 8, { esc = "close" })]])
	escape()
	eq(child.lua_get("floats()"), 0)

	child.lua([[
		left = 0
		open_many(40, 8, { on_input_leave = function() left = left + 1 end })
	]])
	escape()
	eq(child.lua_get("left"), 1)
end

T["core"]["it can stay open, and let the focus go elsewhere"] = function()
	child.lua([[
		origin = vim.api.nvim_get_current_win()
		picks = {}
		open_many(40, 8, {
			close_on_select = false,
			auto_close = false,
			on_select = function(value) picks[#picks + 1] = value end,
		})
	]])
	type("<C-j><CR><C-j><CR>")
	eq(child.lua_get("picks"), { 2, 3 })
	eq(child.lua_get("floats()"), 2)
	child.lua("vim.api.nvim_set_current_win(origin); vim.wait(20, function() return false end, 5)")
	eq(child.lua_get("floats()"), 2)
	child.lua("picker:close()")
	eq(child.lua_get("floats()"), 0)
end

T["layouts"] = new_set()

T["layouts"]["a column on the right"] = function()
	child.lua([[open_many(40, 0, { layout = "right", width = 0.4, height = nil })]])
	child.lua("vim.wait(20, function() return false end, 5); reactive.flush()")
	eq(child.fn.mode(), "i")
	-- The prompt is on the right half of the editor, and the list below it.
	eq(child.lua_get("vim.fn.win_screenpos(0)[2] > vim.o.columns / 2"), true)
	eq(child.lua_get("list_lines()[1]"), "▌ item 01")
	type("17")
	type("<CR>")
	eq(child.lua_get("picked"), 17)
	eq(child.lua_get("floats()"), 0)
end

T["layouts"]["windows of the caller's own"] = function()
	child.lua([[
		picker = Markup.picker({
			items = { { label = "one", value = 1 }, { label = "two", value = 2 } },
			on_select = function(v) picked = v end,
			layout = function(p)
				header = vim.api.nvim_open_win(vim.api.nvim_create_buf(false, true), false, {
					relative = "editor", row = 1, col = 1, width = 30, height = 1,
				})
				local input = vim.api.nvim_create_buf(false, true)
				local input_win = vim.api.nvim_open_win(input, true, {
					relative = "editor", row = 3, col = 1, width = 30, height = 1,
				})
				local list = Markup.window({
					position = "float", relative = "editor", row = 5, col = 1,
					width = 30, height = 5, enter = false,
				})
				p:own(header)
				p:attach_input(input, input_win)
				p:attach_list(list)
				p:on_cleanup(function()
					pcall(vim.api.nvim_win_close, header, true)
					pcall(vim.api.nvim_win_close, input_win, true)
					list:close()
				end)
				vim.cmd.startinsert()
			end,
		})
		reactive.flush()
	]])
	eq(child.lua_get("list_lines()"), { "▌ one", "  two" })
	-- A window that is the picker's does not close it.
	child.lua("vim.api.nvim_set_current_win(header); vim.wait(20, function() return false end, 5)")
	eq(child.lua_get("floats()"), 3)
	child.lua(
		"vim.api.nvim_set_current_win(vim.fn.win_getid(1)); vim.wait(20, function() return false end, 5)"
	)
	eq(child.lua_get("floats()"), 0)
end

return T
