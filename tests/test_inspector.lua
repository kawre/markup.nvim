---@module 'mini.test'

local new_set = MiniTest.new_set
local eq = MiniTest.expect.equality
local child = MiniTest.new_child_neovim()

local T = new_set({
	hooks = {
		pre_case = function()
			child.restart({ "-u", "scripts/minimal_init.lua" })
			child.o.lines, child.o.columns = 40, 120
			child.lua([[
				m = require("markup")
				reactive = require("markup.reactive")
				tree = Markup.devkit.tree()
				win = Markup.window({ position = "current", hijack = true, show = false, minimal = false })
				win.buf = vim.api.nvim_get_current_buf()
				win:show()
				view = Markup.view(win)

				function open()
					inspector = tree.toggle(view)
					reactive.flush()
				end

				function inspector_lines()
					local lines = vim.api.nvim_buf_get_lines(inspector.win.buf, 0, -1, false)
					return vim.tbl_map(function(line)
						return (line:gsub("%s+$", ""))
					end, lines)
				end

				function detail(label)
					for _, row in ipairs(inspector.details()) do
						if row[1] == label then
							return row[2]
						end
					end
				end

				function panel_lines()
					return vim.api.nvim_buf_get_lines(inspector.details_win.buf, 0, -1, false)
				end

				function winbar()
					return (vim.wo[inspector.win.win].winbar:gsub("%%#%w+#", ""))
				end

				function contains(text)
					for _, line in ipairs(inspector_lines()) do
						if line:find(text, 1, true) then
							return true
						end
					end
					return false
				end
			]])
		end,
		post_once = function()
			child.stop()
		end,
	},
})

local function run(code)
	child.lua(code)
end

local function contains(text)
	return child.lua_get(("contains(%q)"):format(text))
end

T["shows the root and its first level"] = function()
	run([[
		view:render(m.block({ m.block("hello") }))
		open()
	]])
	eq(contains("block"), true)
end

T["layout"] = new_set()

T["layout"]["keeps stats in the winbar while the tree scrolls"] = function()
	run([[
		local rows = {}
		for i = 1, 500 do
			rows[i] = m.block("row " .. i)
		end
		view:render(m.block(rows))
		open()
		vim.api.nvim_set_current_win(win.win)
		vim.api.nvim_win_set_cursor(win.win, { 1, 0 })
		inspector:follow_cursor()
		vim.api.nvim_set_current_win(inspector.win.win)
		vim.cmd("normal! G")
		reactive.flush()
	]])
	eq(child.lua_get("winbar():find('nodes', 1, true) ~= nil"), true)
	eq(child.lua_get("winbar():find('effects', 1, true) ~= nil"), true)
	eq(child.lua_get("vim.fn.line('w0') > 1"), true)
end

T["layout"]["shows the frame time and flags"] = function()
	run([[
		view:render(m.block("hello"))
		open()
	]])
	eq(child.lua_get("winbar():find(' ms', 1, true) ~= nil"), true)
	eq(child.lua_get("winbar():find('● follow', 1, true) ~= nil"), true)
	eq(child.lua_get("winbar():find('○ groups', 1, true) ~= nil"), true)
end

T["layout"]["takes its share of the screen and fits the winbar"] = function()
	run([[
		local rows = {}
		for i = 1, 50000 do
			rows[i] = m.block({ m.inline("x") })
		end
		view:render(m.block(rows))
		open()
	]])
	eq(child.lua_get("vim.api.nvim_win_get_width(inspector.win.win)"), 48)
	-- `equalize` runs after the event loop turns.
	run([[vim.wait(50)]])
	eq(child.lua_get("vim.api.nvim_win_get_width(inspector.win.win)"), 48)
	eq(child.lua_get("vim.api.nvim_eval_statusline(vim.wo[inspector.win.win].winbar, { maxwidth = 48, winid = inspector.win.win }).str:find('groups', 1, true) ~= nil"), true)
end

T["layout"]["keeps its width next to other bottom splits"] = function()
	run([[
		other = Markup.window({ relative = "win", win = win.win, position = "bottom", enter = false })
		view:render(m.block("a"))
		open()
		vim.wait(50)
	]])
	eq(child.lua_get("vim.api.nvim_win_get_width(inspector.win.win)"), 48)
end

T["layout"]["updates the winbar when a flag changes"] = function()
	run([[
		view:render(m.block("hello"))
		open()
		vim.api.nvim_set_current_win(inspector.win.win)
	]])
	child.type_keys("c")
	eq(child.lua_get("winbar():find('● groups', 1, true) ~= nil"), true)
end

T["layout"]["the tree buffer only holds rows"] = function()
	run([[
		view:render(m.block({ m.block("a"), m.block("b") }))
		open()
	]])
	eq(child.lua_get("#inspector_lines() == #inspector.rows()"), true)
end

T["layout"]["details have their own pane"] = function()
	run([[
		view:render(m.block({ m.block("one") }))
		open()
		vim.api.nvim_set_current_win(win.win)
		vim.api.nvim_win_set_cursor(win.win, { 1, 0 })
		inspector:follow_cursor()
		reactive.flush()
	]])
	eq(child.lua_get("#panel_lines()"), 8)
	eq(child.lua_get("panel_lines()[6]"):find('"one"', 1, true) ~= nil, true)
	eq(child.lua_get("panel_lines()[8]"):find("<CR> open", 1, true) ~= nil, true)
end

T["layout"]["aligns geometry to the right edge"] = function()
	run([[
		view:render(m.block({ m.block("a") }))
		open()
		width = vim.api.nvim_win_get_width(inspector.win.win)
	]])
	local line = child.lua_get("inspector_lines()[1]")
	local geometry = line:match("%d+,%d+  %d+×%d+$")
	eq(geometry ~= nil, true)
	eq(child.lua_get(("vim.fn.strdisplaywidth(%q)"):format(line)), child.lua_get("width") - 1)
end

T["layout"]["drops geometry on narrow windows"] = function()
	run([[
		view:render(m.block({ m.block("a very long text that does not fit in the narrow window at all") }))
		open()
		vim.api.nvim_win_set_width(inspector.win.win, 20)
		vim.api.nvim_set_current_win(win.win)
		vim.api.nvim_win_set_cursor(win.win, { 1, 0 })
		inspector:follow_cursor()
		reactive.flush()
	]])
	eq(child.lua_get("inspector_lines()[3]"):match("%d+×%d+"), nil)
end

T["layout"]["draws highlight names in their own highlight"] = function()
	run([[
		view:render(m.block({ m.inline("a", "Label") }))
		open()
		vim.api.nvim_set_current_win(win.win)
		vim.api.nvim_win_set_cursor(win.win, { 1, 0 })
		inspector:follow_cursor()
		reactive.flush()
	]])
	eq(contains(" Label"), true)
	local groups = child.lua_get([[vim.tbl_map(function(mark)
		return mark[4].hl_group
	end, vim.api.nvim_buf_get_extmarks(inspector.win.buf, inspector.view.ns, 0, -1, { details = true }))]])
	eq(vim.tbl_contains(groups, "Label"), true)
end

T["layout"]["recolors after a colorscheme change"] = function()
	run([[
		view:render(m.block("a"))
		open()
		vim.api.nvim_set_hl(0, "MarkupInspectorBarGood", {})
		vim.api.nvim_exec_autocmds("ColorScheme", {})
	]])
	eq(child.lua_get("next(vim.api.nvim_get_hl(0, { name = 'MarkupInspectorBarGood' })) ~= nil"), true)
end

T["collapses and expands rows with the keyboard"] = function()
	run([[
		view:render(m.block({ m.block("hello") }))
		open()
		vim.api.nvim_set_current_win(win.win)
		vim.api.nvim_win_set_cursor(win.win, { 1, 0 })
		inspector:follow_cursor()
		vim.api.nvim_set_current_win(inspector.win.win)
		vim.api.nvim_win_set_cursor(inspector.win.win, { 2, 0 })
	]])
	eq(contains('"hello"'), true)

	child.type_keys("<CR>")
	run("reactive.flush()")
	eq(contains('"hello"'), false)

	child.type_keys("<CR>")
	run("reactive.flush()")
	eq(contains('"hello"'), true)
end

T["moving the cursor selects the row"] = function()
	run([[
		view:render(m.block({ m.block("one"), m.block("two") }))
		open()
		vim.api.nvim_set_current_win(inspector.win.win)
		vim.api.nvim_win_set_cursor(inspector.win.win, { 1, 0 })
	]])
	child.type_keys("j")
	eq(child.lua_get("inspector.selected() ~= 1"), true)
end

T["closes with q"] = function()
	run([[
		view:render(m.block("hello"))
		open()
		vim.api.nvim_set_current_win(inspector.win.win)
	]])
	child.type_keys("q")
	eq(child.lua_get("tree.get(view) == nil"), true)
end

T["follows a real window resize"] = function()
	run([[
		view:render(m.block({ m.block({ "a", style = "Label" }) }))
		width = vim.api.nvim_win_get_width(win.win)
		vim.cmd("vsplit")
		vim.wait(200, function()
			reactive.flush()
			return view.engine:describe(1).outer_width ~= width
		end, 10)
	]])
	eq(child.lua_get("view.engine:describe(1).outer_width == vim.api.nvim_win_get_width(win.win)"), true)
end

T["keeps up with the target"] = function()
	run([[
		name = m.signal("before")
		view:render(m.block({ m.block(name) }))
		open()
		vim.api.nvim_set_current_win(win.win)
		vim.api.nvim_win_set_cursor(win.win, { 1, 0 })
		inspector:follow_cursor()
	]])
	eq(contains('"before"'), true)

	run([[
		name("after")
		reactive.flush()
		vim.wait(300, function() return contains('"after"') end, 10)
	]])
	eq(contains('"after"'), true)
end

T["follow selects the node under the cursor"] = function()
	run([[
		view:render(m.block({ m.block("one"), m.block({ m.inline("two ", "Label"), m.inline("three") }) }))
		open()
		vim.api.nvim_set_current_win(win.win)
		vim.api.nvim_win_set_cursor(win.win, { 2, 5 })
		inspector:follow_cursor()
	]])
	eq(child.lua_get("detail('text')"), '"three"')
end

T["marks the selected node in the target"] = function()
	run([[
		view:render(m.block({ m.block("one"), m.block("two") }))
		open()
		vim.api.nvim_set_current_win(win.win)
		vim.api.nvim_win_set_cursor(win.win, { 2, 0 })
		inspector:follow_cursor()
	]])
	local marks = child.lua_get([[vim.tbl_map(function(mark)
		return { mark[2], mark[3], mark[4].end_col }
	end, vim.api.nvim_buf_get_extmarks(win.buf, inspector.ns, 0, -1, { details = true }))]])
	eq(marks, { { 1, 0, 3 } })
end

T["hides groups until asked"] = function()
	run([[
		local Comp = m.component(function() return m.block("x") end)
		view:render(m.block({ Comp() }))
		open()
		vim.api.nvim_set_current_win(win.win)
		vim.api.nvim_win_set_cursor(win.win, { 1, 0 })
		inspector:follow_cursor()
	]])
	eq(contains("group"), false)

	run([[
		inspector.show_groups = true
		inspector:refresh()
		reactive.flush()
	]])
	eq(contains("group"), true)
end

T["pages huge child lists"] = function()
	run([[
		local rows = {}
		for i = 1, 5000 do
			rows[i] = m.block("row " .. i)
		end
		view:render(m.block(rows))
		open()
		vim.api.nvim_set_current_win(win.win)
		vim.api.nvim_win_set_cursor(win.win, { 1, 0 })
		inspector:follow_cursor()
	]])
	eq(child.lua_get("#inspector.rows() < 150"), true)
	eq(contains("more"), true)
end

T["pages lists spread over nested groups"] = function()
	run([[
		local function Level(depth)
			local rows = {}
			for i = 1, 60 do
				rows[i] = m.block("row " .. depth .. " " .. i)
			end
			return {
				rows,
				depth < 40 and m.show(function() return true end, function()
					return Level(depth + 1)
				end) or nil,
			}
		end
		view:render(m.block(Level(1)))
		open()
		vim.api.nvim_set_current_win(win.win)
		vim.api.nvim_win_set_cursor(win.win, { 2000, 0 })
		inspector:follow_cursor()
	]])
	eq(child.lua_get("#inspector.rows() < 150"), true)
	eq(child.lua_get("detail('text')"), '"row 34 20"')
	eq(contains('"row 34 20"'), true)
end

T["follow reaches rows beyond the first page"] = function()
	run([[
		local rows = {}
		for i = 1, 5000 do
			rows[i] = m.block("row " .. i)
		end
		view:render(m.block(rows))
		open()
		vim.api.nvim_set_current_win(win.win)
		vim.api.nvim_win_set_cursor(win.win, { 4000, 0 })
		inspector:follow_cursor()
	]])
	eq(child.lua_get("detail('text')"), '"row 4000"')
	eq(contains('"row 4000"'), true)
	eq(contains("earlier"), true)
end

T["closing removes everything"] = function()
	run([[
		view:render(m.block("hello"))
		before = reactive.stats()
		open()
		inspector:close()
		reactive.flush()
	]])
	eq(child.lua_get("reactive.stats().effects == before.effects"), true)
	eq(child.lua_get("reactive.stats().scopes == before.scopes"), true)
	eq(child.lua_get("tree.get(view) == nil"), true)
	eq(child.lua_get("#vim.api.nvim_tabpage_list_wins(0)"), 1)
	eq(child.lua_get("#vim.api.nvim_buf_get_extmarks(win.buf, inspector.ns, 0, -1, {})"), 0)
end

T["closing the inspector window cleans up"] = function()
	run([[
		view:render(m.block("hello"))
		open()
		vim.api.nvim_win_close(inspector.win.win, true)
		vim.wait(100, function() return tree.get(view) == nil end, 10)
	]])
	eq(child.lua_get("tree.get(view) == nil"), true)
end

T["does nothing while closed"] = function()
	run([[
		name = m.signal("a")
		view:render(m.block(name))
		open()
		inspector:close()
		name("b")
		reactive.flush()
		vim.wait(150)
	]])
	eq(child.lua_get([[#vim.api.nvim_get_autocmds({ pattern = "MarkupViewCommit" .. win.id })]]), 0)
end

T["refreshes are throttled"] = function()
	run([[
		count = m.signal(0)
		view:render(m.block(count))
		open()
		refreshes = 0
		local refresh = inspector.refresh
		inspector.refresh = function(...)
			refreshes = refreshes + 1
			return refresh(...)
		end
		for i = 1, 200 do
			count(i)
			reactive.flush()
		end
		vim.wait(150)
	]])
	eq(child.lua_get("refreshes <= 2"), true)
end

T["the command toggles the inspector"] = function()
	run([[
		view:render(m.block("hello"))
		require("markup").setup({})
		vim.cmd("Markup inspect")
		reactive.flush()
	]])
	eq(child.lua_get("tree.get(view) ~= nil"), true)

	run([[vim.cmd("Markup inspect")]])
	eq(child.lua_get("tree.get(view) == nil"), true)
end

T["reports live effects"] = function()
	run([[
		open_flag = m.signal(false)
		view:render(m.show(open_flag, function()
			return m.block(function() return "x" end)
		end))
		open()
		base = reactive.stats().effects
		for _ = 1, 10 do
			open_flag(true)
			reactive.flush()
			open_flag(false)
			reactive.flush()
		end
	]])
	eq(child.lua_get("reactive.stats().effects == base"), true)
end

return T
