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

				function stats_lines()
					return vim.tbl_map(function(line)
						return (line:gsub("%s+$", ""))
					end, vim.api.nvim_buf_get_lines(inspector.stats_win.buf, 0, -1, false))
				end

				function stats_text()
					return table.concat(stats_lines(), "\n")
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

T["marks a node that reaches past the edge"] = function()
	child.lua([[
		errors = {}
		vim.notify = function(message) errors[#errors + 1] = message end
		-- Moved half out of the window, as while a page slides in.
		view:render(m.block({ position = "relative", left = -4, m.block("sliding in") }))
		reactive.flush()
		open()
		for id = 1, view.last_id do
			local ok, node = pcall(view.engine.describe, view.engine, id)
			if ok and node.x and node.x < 0 then
				inspector:select(id)
				moved = node
			end
		end
		marks = #vim.api.nvim_buf_get_extmarks(win.buf, inspector.ns, 0, -1, {})
	]])
	eq(child.lua_get("moved ~= nil"), true)
	eq(child.lua_get("errors"), {})
	eq(child.lua_get("marks > 0"), true)
end

T["marks nothing of a node out of sight"] = function()
	child.lua([[
		view:render(m.block({ position = "relative", left = -200, m.block("gone") }))
		reactive.flush()
		open()
		for id = 1, view.last_id do
			local ok, node = pcall(view.engine.describe, view.engine, id)
			if ok and node.x and node.x < -100 then inspector:select(id) end
		end
		marks = #vim.api.nvim_buf_get_extmarks(win.buf, inspector.ns, 0, -1, {})
	]])
	eq(child.lua_get("marks"), 0)
end

T["layout"] = new_set()

T["layout"]["keeps stats in their own pane while the tree scrolls"] = function()
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
	eq(child.lua_get("stats_text():find('effects', 1, true) ~= nil"), true)
	eq(child.lua_get("vim.fn.line('w0') > 1"), true)
end

T["layout"]["shows the frame time and flags"] = function()
	run([[
		view:render(m.block("hello"))
		open()
	]])
	eq(child.lua_get("stats_text():find(' ms', 1, true) ~= nil"), true)
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

T["stats"] = new_set()

T["stats"]["counts frames per second and keeps a sparkline"] = function()
	run([[
		count = m.signal(0)
		view:render(m.block({ function() return tostring(count()) end }))
		open()
		for i = 1, 5 do
			count(i)
			reactive.flush()
		end
		inspector:update_perf()
		reactive.flush()
	]])
	eq(child.lua_get("inspector.perf().fps") >= 5, true)
	eq(child.lua_get("#inspector.perf().frames") >= 5, true)
	eq(child.lua_get("stats_lines()[1]"):match("(%d+) fps") ~= nil, true)
	eq(child.lua_get("stats_lines()[1]"):find("[▁▂▃▄▅▆▇█]") ~= nil, true)
end

T["stats"]["counts more frames per second than the sparkline keeps"] = function()
	run([[
		count = m.signal(0)
		view:render(m.block({ function() return tostring(count()) end }))
		open()
		for i = 1, 300 do
			count(i)
			reactive.flush()
		end
		inspector:update_perf()
	]])
	eq(child.lua_get("inspector.perf().fps") >= 300, true)
	eq(child.lua_get("#inspector.perf().frames"), 120)
end

T["stats"]["forgets frames older than a second"] = function()
	run([[
		count = m.signal(0)
		view:render(m.block({ function() return tostring(count()) end }))
		open()
		for i = 1, 5 do
			count(i)
			reactive.flush()
		end
		vim.wait(1100, function() return false end, 50)
		inspector:update_perf()
	]])
	eq(child.lua_get("inspector.perf().fps"), 0)
end

T["stats"]["shows the phases of a frame and what the view is made of"] = function()
	run([[
		view:render(m.block({ m.block("a"), m.block("b") }))
		open()
	]])
	local text = child.lua_get("stats_text()")
	for _, word in ipairs({ "layout", "paint", "diff", "write", "nodes", "effects", "scopes", "anim", "MB", "lines", "ticks" }) do
		eq(text:find(word, 1, true) ~= nil, true)
	end
end

T["stats"]["counts running animations"] = function()
	run([[
		Markup.animate.manual = true
		Markup.animate.enabled = true
		value = m.animated(0, { duration = 500 })
		view:render(m.block({ function() return tostring(value()) end }))
		value(10)
		reactive.flush()
		open()
		inspector:update_perf()
	]])
	eq(child.lua_get("inspector.perf().animations"), 1)
end

T["stats"]["stops its clock on close"] = function()
	run([[
		view:render(m.block("x"))
		open()
		timer = inspector.timer
		inspector:close()
	]])
	eq(child.lua_get("timer:is_closing()"), true)
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
	local lines = child.lua_get("panel_lines()")
	eq(#lines, 9)
	eq(lines[1]:find('"one"', 1, true) ~= nil, true)
	eq(table.concat(lines, "\n"):find("margin", 1, true) ~= nil, true)
	eq(lines[8]:find('"one"', 1, true) ~= nil, true)
	eq(lines[9]:find("<CR> open", 1, true) ~= nil, true)
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

T["marking the selection can be turned off"] = function()
	run([[
		view:render(m.block({ m.block("one"), m.block("two") }))
		open()
		vim.api.nvim_set_current_win(win.win)
		vim.api.nvim_win_set_cursor(win.win, { 2, 0 })
		inspector:follow_cursor()
		before = #vim.api.nvim_buf_get_extmarks(win.buf, inspector.ns, 0, -1, {})
		vim.api.nvim_set_current_win(inspector.win.win)
		vim.cmd("normal m")
		after = #vim.api.nvim_buf_get_extmarks(win.buf, inspector.ns, 0, -1, {})
		vim.api.nvim_set_current_win(win.win)
		vim.api.nvim_win_set_cursor(win.win, { 1, 0 })
		inspector:follow_cursor()
		moved = #vim.api.nvim_buf_get_extmarks(win.buf, inspector.ns, 0, -1, {})
	]])
	eq(child.lua_get("before") > 0, true)
	eq(child.lua_get("after"), 0)
	eq(child.lua_get("moved"), 0)
	eq(child.lua_get("winbar():find('○ mark', 1, true) ~= nil"), true)
end

T["marking can be off from the start"] = function()
	run([[
		m.setup({ inspector = { mark = false } })
		view:render(m.block({ m.block("one") }))
		open()
		vim.api.nvim_set_current_win(win.win)
		vim.api.nvim_win_set_cursor(win.win, { 1, 0 })
		inspector:follow_cursor()
	]])
	eq(child.lua_get("#vim.api.nvim_buf_get_extmarks(win.buf, inspector.ns, 0, -1, {})"), 0)
	eq(child.lua_get("Markup.config.user.logging"), true)
end

T["options"] = new_set()

local function open_options()
	run([[
		view:render(m.block({ m.block({ "hello", style = "Label" }) }))
		open()
		vim.api.nvim_set_current_win(inspector.win.win)
		vim.cmd("normal s")
		reactive.flush()
		options = inspector.options_view
		function option_row(label)
			for i, line in ipairs(vim.api.nvim_buf_get_lines(inspector.options_win.buf, 0, -1, false)) do
				if line:find(label, 1, true) then return i end
			end
		end
		function press(label)
			vim.api.nvim_win_set_cursor(inspector.options_win.win, { option_row(label), 2 })
			vim.cmd("doautocmd CursorMoved")
			reactive.flush()
			vim.cmd("normal \r")
			reactive.flush()
		end
	]])
end

T["options"]["opens a popup listing every option"] = function()
	open_options()
	eq(child.lua_get("vim.api.nvim_get_current_win() == inspector.options_win.win"), true)
	for _, label in ipairs({ "Follow cursor", "Show groups", "Mark selection", "Geometry", "Highlight names", "Indent guides", "Live updates", "Variable rate", "Max fps" }) do
		eq(child.lua_get(("option_row(%q) ~= nil"):format(label)), true)
	end
end

T["options"]["toggles what is pressed"] = function()
	open_options()
	run([[press("Geometry")]])
	eq(child.lua_get("inspector.geometry"), false)
	eq(child.lua_get("inspector_lines()[2]"):match("%d+×%d+"), nil)
	run([[press("Highlight names")]])
	eq(contains(" Label"), false)
	run([[press("Indent guides")]])
	eq(child.lua_get("inspector_lines()[2]"):find("│", 1, true), nil)
	run([[press("Mark selection")]])
	eq(child.lua_get("winbar():find('○ mark', 1, true) ~= nil"), true)
	run([[press("Geometry")]])
	eq(child.lua_get("inspector_lines()[2]"):match("%d+×%d+") ~= nil, true)
end

T["options"]["live updates can be paused"] = function()
	open_options()
	run([[
		press("Live updates")
		view:render(m.block({ m.block("later") }))
		reactive.flush()
		vim.wait(250, function() return false end, 10)
	]])
	eq(contains('"later"'), false)
end

T["options"]["a slider sets the frame rate"] = function()
	open_options()
	run([[
		vim.api.nvim_win_set_cursor(inspector.options_win.win, { option_row("Max fps"), 2 })
		vim.cmd("doautocmd CursorMoved")
		reactive.flush()
		before = Markup.animate.fps
		vim.cmd("normal l")
		reactive.flush()
		up = Markup.animate.fps
		for _ = 1, 10 do vim.cmd("normal l") end
		reactive.flush()
		top = Markup.animate.fps
		top_line = vim.api.nvim_buf_get_lines(inspector.options_win.buf, option_row("Max fps") - 1, option_row("Max fps"), false)[1]
		for _ = 1, 20 do vim.cmd("normal h") end
		bottom = Markup.animate.fps
	]])
	eq(child.lua_get("before"), 30)
	eq(child.lua_get("up"), 60)
	eq(child.lua_get("top == math.huge"), true)
	eq(child.lua_get("top_line"):find("unlimited", 1, true) ~= nil, true)
	eq(child.lua_get("bottom"), 15)
end

T["options"]["the slider stops at the configured rate"] = function()
	run([[
		m.setup({ animate = { fps = 200 } })
	]])
	open_options()
	run([[
		row = option_row("Max fps")
		line = vim.api.nvim_buf_get_lines(inspector.options_win.buf, row - 1, row, false)[1]
		vim.api.nvim_win_set_cursor(inspector.options_win.win, { row, 2 })
		vim.cmd("doautocmd CursorMoved")
		reactive.flush()
		vim.cmd("normal h")
		lower = Markup.animate.fps
		vim.cmd("normal l")
		back = Markup.animate.fps
	]])
	eq(child.lua_get("line"):find("200", 1, true) ~= nil, true)
	eq(child.lua_get("lower"), 180)
	eq(child.lua_get("back"), 200)
end

T["options"]["variable rate turns vrr off everywhere"] = function()
	open_options()
	run([[press("Variable rate")]])
	eq(child.lua_get("Markup.animate.vrr"), false)
	run([[press("Variable rate")]])
	eq(child.lua_get("Markup.animate.vrr"), true)
end

T["options"]["defaults come from setup"] = function()
	run([[
		m.setup({ inspector = { geometry = false, guides = false } })
		view:render(m.block({ m.block("one") }))
		open()
	]])
	eq(child.lua_get("inspector.geometry"), false)
	eq(child.lua_get("inspector.guides"), false)
	eq(child.lua_get("inspector.follow"), true)
end

T["options"]["closes with q and with the inspector"] = function()
	open_options()
	run([[
		vim.cmd("normal q")
		closed_with_q = inspector.options_win == nil
		back_in_tree = vim.api.nvim_get_current_win() == inspector.win.win
		vim.cmd("normal s")
		popup = inspector.options_win.win
		inspector:close()
	]])
	eq(child.lua_get("closed_with_q"), true)
	eq(child.lua_get("back_in_tree"), true)
	eq(child.lua_get("vim.api.nvim_win_is_valid(popup)"), false)
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

T["stress test"] = new_set()

T["stress test"]["runs with the inspector open and closes with q"] = function()
	run([[
		errors = {}
		vim.notify = function(message) errors[#errors + 1] = message end
		stress = Markup.playground.stress_test()
		vim.wait(800, function() return false end, 20)
		stress_inspector = tree.get(stress)
		uncapped = Markup.animate.fps == math.huge
		frames = #stress_inspector.samples
		vim.cmd("normal +")
		vim.wait(300, function() return false end, 20)
		tabs = #vim.api.nvim_list_tabpages()
		vim.cmd("normal q")
		vim.wait(100, function() return false end, 10)
	]])
	eq(child.lua_get("errors"), {})
	eq(child.lua_get("frames") > 5, true)
	eq(child.lua_get("Markup.animate.fps"), 30)
	eq(child.lua_get("tabs"), 2)
	eq(child.lua_get("uncapped"), true)
	eq(child.lua_get("#vim.api.nvim_list_tabpages()"), 1)
	eq(child.lua_get("tree.get(stress) == nil"), true)
	eq(child.lua_get("type(require('markup.cmd').commands.playground.stress_test[1])"), "function")
end

T["stress test"]["gives the frame rate back however its tab closes"] = function()
	run([[
		Markup.playground.stress_test()
		vim.wait(100, function() return false end, 10)
		vim.cmd("tabclose")
		vim.wait(50, function() return false end, 10)
	]])
	eq(child.lua_get("Markup.animate.fps"), 30)
end

return T
