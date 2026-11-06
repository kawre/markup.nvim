---@module 'mini.test'

local new_set = MiniTest.new_set
local expect, eq = MiniTest.expect, MiniTest.expect.equality
local child = MiniTest.new_child_neovim()

local T = new_set({
	hooks = {
		pre_case = function()
			child.restart({ "-u", "scripts/minimal_init.lua" })
			child.o.lines, child.o.columns = 15, 60
			child.lua([[
				m = require("markup")
				reactive = require("markup.reactive")
				win = Markup.window({ position = "current", hijack = true, show = false, minimal = false })
				win.buf = vim.api.nvim_get_current_buf()
				win:show()
				view = Markup.view(win)
				function lines()
					local result = vim.api.nvim_buf_get_lines(win.buf, 0, -1, false)
					return vim.tbl_map(function(line)
						return (line:gsub("%s+$", ""))
					end, result)
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

local function lines()
	return child.lua_get("lines()")
end

local function marks()
	return child.lua_get([[vim.tbl_map(function(mark)
		return { mark[2], mark[3], mark[4].end_col, mark[4].hl_group }
	end, vim.api.nvim_buf_get_extmarks(win.buf, view.ns, 0, -1, { details = true }))]])
end

T["static"] = new_set()

T["static"]["renders text in blocks"] = function()
	run([[view:render(m.block({ m.block("one"), m.block("two") }))]])
	eq(lines(), { "one", "two" })
end

T["static"]["keeps inline runs on one line"] = function()
	run([[view:render(m.block({ m.inline("a "), m.inline("b"), m.block("c") }))]])
	eq(lines(), { "a b", "c" })
end

T["static"]["applies margin, padding and spacing"] = function()
	run([[view:render(m.block({
		spacing = 1,
		m.block({ "a", margin_left = 2 }),
		m.block({ "b", padding = { 0, 0, 0, 3 } }),
	}))]])
	eq(lines(), { "  a", "", "   b" })
end

T["static"]["accepts numbers, lists and nothing"] = function()
	run([[view:render(m.block({ m.inline(1), false, { m.inline(2), { m.inline(3) } } }))]])
	eq(lines(), { "123" })
end

T["static"]["rejects layouts the engine lacks"] = function()
	expect.error(function()
		run([[view:render(m.inblock("a"))]])
	end, "not implemented")
end

T["flex"] = new_set()

T["flex"]["lays items out in a row"] = function()
	run([[view:render(m.flex({ gap = 1, m.block("a"), m.block("bb"), m.block("c") }))]])
	eq(lines(), { "a bb c" })
end

T["flex"]["pushes items apart"] = function()
	run([[view:render(m.flex({ width = 20, justify = "between", m.block("left"), m.block("right") }))]])
	eq(lines(), { "left           right" })
end

T["flex"]["grows an item into free space"] = function()
	run([[view:render(m.flex({ width = 20, m.block({ "a", grow = 1 }), m.block("end") }))]])
	eq(lines(), { "a                end" })
end

T["flex"]["stacks with vflex and vertical"] = function()
	run([[view:render(m.block({ m.vflex({ m.block("a"), m.block("b") }), m.flex({ vertical = true, m.block("c") }) }))]])
	eq(lines(), { "a", "b", "c" })
end

T["flex"]["centers on both axes"] = function()
	run([[view:render(m.flex({
		width = 9, height = 3, justify = "center", align = "center", m.block("x"),
	}))]])
	eq(lines(), { "", "    x", "" })
end

T["flex"]["wraps"] = function()
	run([[view:render(m.flex({
		width = 8, wrap = true, gap = { 1, 2 },
		m.block("aaa"), m.block("bbb"), m.block("ccc"),
	}))]])
	eq(lines(), { "aaa  bbb", "", "ccc" })
end

T["flex"]["updates when a child changes size"] = function()
	run([[
		name = m.signal("a")
		view:render(m.flex({ gap = 1, m.block(name), m.block("end") }))
		name("longer")
		reactive.flush()
	]])
	eq(lines(), { "longer end" })
end

T["flex"]["dynamic props relayout"] = function()
	run([[
		side = m.signal("start")
		view:render(m.flex({ width = 6, justify = side, m.block("x") }))
		side("end")
		reactive.flush()
	]])
	eq(lines(), { "     x" })
end

T["flex"]["show and each flow inside"] = function()
	run([[
		open, items = m.signal(false), m.signal({ "a", "b" })
		view:render(m.flex({
			gap = 1,
			m.show(open, m.block("shown")),
			m.each(items, function(item) return m.block(item) end),
		}))
		open(true)
		items({ "b", "c" })
		reactive.flush()
	]])
	eq(lines(), { "shown b c" })
end

T["flex"]["rejects unknown values"] = function()
	expect.error(function()
		run([[view:render(m.flex({ justify = "sideways", m.block("x") }))]])
	end, "invalid justify")
end

T["grid"] = new_set()

T["grid"]["places cells in tracks"] = function()
	run([[view:render(m.grid({
		columns = { 3, 3 },
		m.block("a"), m.block("b"), m.block("c"), m.block("d"),
	}))]])
	eq(lines(), { "a  b", "c  d" })
end

T["grid"]["mixes fixed, auto and fractional tracks"] = function()
	run([[view:render(m.grid({
		width = 20, columns = { 4, "auto", "1fr" },
		m.block("a"), m.block("bb"), m.block("c"),
	}))]])
	eq(lines(), { "a   bbc" })
end

T["grid"]["makes equal tracks from a number"] = function()
	run([[view:render(m.grid({ width = 9, columns = 3, m.block("a"), m.block("b"), m.block("c") }))]])
	eq(lines(), { "a  b  c" })
end

T["grid"]["places and spans explicitly"] = function()
	run([[view:render(m.grid({
		columns = { 2, 2, 2 },
		m.block({ "x", column = 3, row = 2 }),
		m.block({ "wide", column = 1, row = 1, column_span = 2 }),
	}))]])
	eq(lines(), { "wide", "    x" })
end

T["grid"]["applies gaps"] = function()
	run([[view:render(m.grid({
		columns = { 1, 1 }, gap = { 1, 2 },
		m.block("a"), m.block("b"), m.block("c"), m.block("d"),
	}))]])
	eq(lines(), { "a  b", "", "c  d" })
end

T["grid"]["rejects bad tracks"] = function()
	expect.error(function()
		run([[view:render(m.grid({ columns = { "wide" }, m.block("x") }))]])
	end, "invalid grid track")
end

T["absolute"] = new_set()

T["absolute"]["overlays what is in flow"] = function()
	run([[view:render(m.block({
		m.block("abcdefgh"),
		m.block({ "XY", position = "absolute", top = 0, left = 2 }),
	}))]])
	eq(lines(), { "abXYefgh" })
end

T["absolute"]["does not take space in flow"] = function()
	run([[view:render(m.block({
		m.block("a"),
		m.block({ "over", position = "absolute", top = 0, left = 4 }),
		m.block("b"),
	}))]])
	eq(lines(), { "a   over", "b" })
end

T["absolute"]["ignores static parents"] = function()
	run([[view:render(m.block({
		width = 10,
		m.block({ "x", position = "absolute", right = 0, top = 0 }),
	}))]])
	eq(lines()[1]:sub(-1), "x")
	eq(#lines()[1], child.lua_get("vim.api.nvim_win_get_width(win.win)"))
end

T["absolute"]["anchors to the far edges"] = function()
	run([[view:render(m.block({
		width = 10, height = 3, position = "relative",
		m.block({ "x", position = "absolute", right = 0, bottom = 0 }),
	}))]])
	eq(lines(), { "", "", "         x" })
end

T["absolute"]["uses the nearest positioned ancestor"] = function()
	run([[view:render(m.block({
		m.block("first"),
		m.block({
			position = "relative", margin_left = 3,
			m.block("base"),
			m.block({ "z", position = "absolute", top = 0, left = 1 }),
		}),
	}))]])
	eq(lines(), { "first", "   bzse" })
end

T["absolute"]["stretches between opposite offsets"] = function()
	run([[view:render(m.block({
		width = 10, height = 3, position = "relative",
		m.block({ position = "absolute", left = 2, right = 2, top = 1, bottom = 1, style = "Label" }),
	}))]])
	eq(marks(), { { 1, 2, 8, "Label" } })
end

T["absolute"]["higher z wins"] = function()
	run([[view:render(m.block({
		m.block({ "bbbb", position = "absolute", top = 0, left = 1, z = 2 }),
		m.block({ "aaaaaa", position = "absolute", top = 0, left = 0, z = 1 }),
	}))]])
	eq(lines(), { "abbbba" })
end

T["absolute"]["grows the buffer when it reaches past the content"] = function()
	run([[view:render(m.block({
		m.block("a"),
		m.block({ "low", position = "absolute", top = 4, left = 0 }),
	}))]])
	eq(lines(), { "a", "", "", "", "low" })
end

T["absolute"]["toggles with show"] = function()
	run([[
		open = m.signal(true)
		view:render(m.block({
			m.block("under text"),
			m.show(open, m.block({ "POP", position = "absolute", top = 0, left = 2 })),
		}))
	]])
	eq(lines(), { "unPOP text" })

	run([[open(false); reactive.flush()]])
	eq(lines(), { "under text" })
end

T["absolute"]["takes presses before what is underneath"] = function()
	run([[
		pressed = nil
		view:render(m.block({
			m.block({ "under text", on_press = function() pressed = "under" end }),
			m.block({ "TOP", position = "absolute", top = 0, left = 2, on_press = function() pressed = "top" end }),
		}))
		vim.api.nvim_win_set_cursor(0, { 1, 3 })
		view:press()
	]])
	eq(child.lua_get("pressed"), "top")
end

T["relative"] = function()
	run([[view:render(m.block({
		m.block("a"),
		m.block({ "b", position = "relative", left = 3 }),
	}))]])
	eq(lines(), { "a", "   b" })
end

T["highlights"] = new_set()

T["highlights"]["uses byte columns after wide text"] = function()
	run([[view:render(m.block({ m.inline("你", "Label"), m.inline("ab", "String") }))]])
	eq(marks(), { { 0, 0, 3, "Label" }, { 0, 3, 5, "String" } })
end

T["highlights"]["defines groups for style tables"] = function()
	run([[view:render(m.inline("a", { fg = "#ff0000" }))]])
	local group = marks()[1][4]
	eq(child.lua_get(("vim.api.nvim_get_hl(0, { name = %q }).fg"):format(group)), 0xff0000)
end

T["highlights"]["follows a dynamic style"] = function()
	run([[
		color = m.signal("Label")
		view:render(m.inline({ "a", style = color }))
		color("String")
		reactive.flush()
	]])
	eq(marks(), { { 0, 0, 1, "String" } })
end

T["highlights"]["does not pile up across updates"] = function()
	run([[
		count = m.signal(0)
		view:render(m.block({ m.inline(count, "Label") }))
		for i = 1, 5 do
			count(i)
			reactive.flush()
		end
	]])
	eq(#marks(), 1)
end

T["dynamic text"] = new_set()

T["dynamic text"]["updates in place"] = function()
	run([[
		count = m.signal(1)
		view:render(m.block({ m.block("static"), m.block(count) }))
		count(2)
		reactive.flush()
	]])
	eq(lines(), { "static", "2" })
end

T["dynamic text"]["rewrites only the changed line"] = function()
	run([[
		count = m.signal(1)
		local rows = {}
		for i = 1, 100 do
			rows[i] = m.block("row " .. i)
		end
		rows[50] = m.block(count)
		view:render(m.block(rows))
		count(2)
		reactive.flush()
	]])
	eq(child.lua_get("view.stats.lines"), 1)
end

T["dynamic text"]["reflows siblings when the width changes"] = function()
	run([[
		name = m.signal("a")
		view:render(m.block({ m.inline(name), m.inline("|") }))
		name("abc")
		reactive.flush()
	]])
	eq(lines(), { "abc|" })
end

T["dynamic text"]["can switch to an element and back"] = function()
	run([[
		value = m.signal("text")
		view:render(m.block({ value }))
		value(m.block({ m.block("x"), m.block("y") }))
		reactive.flush()
	]])
	eq(lines(), { "x", "y" })

	run([[
		value("text")
		reactive.flush()
	]])
	eq(lines(), { "text" })
end

T["components"] = new_set()

T["components"]["run once"] = function()
	run([[
		runs, count = 0, m.signal(0)
		local Counter = m.component(function(props)
			runs = runs + 1
			return m.block({ props.label, count })
		end)
		view:render(Counter({ label = "n: " }))
		count(1)
		reactive.flush()
	]])
	eq(child.lua_get("runs"), 1)
	eq(lines(), { "n: 1" })
end

T["components"]["share values through context"] = function()
	run([[
		local Child = m.component(function()
			return m.block(m.inject("name"))
		end)
		local Parent = m.component(function()
			m.provide("name", "shared")
			return Child()
		end)
		view:render(Parent())
	]])
	eq(lines(), { "shared" })
end

T["show"] = new_set()

T["show"]["mounts and unmounts its content"] = function()
	run([[
		open = m.signal(false)
		view:render(m.block({ m.block("a"), m.show(open, m.block("b")), m.block("c") }))
	]])
	eq(lines(), { "a", "c" })

	run([[open(true); reactive.flush()]])
	eq(lines(), { "a", "b", "c" })

	run([[open(false); reactive.flush()]])
	eq(lines(), { "a", "c" })
end

T["show"]["renders a fallback"] = function()
	run([[
		open = m.signal(false)
		view:render(m.show(open, m.block("yes"), m.block("no")))
	]])
	eq(lines(), { "no" })
end

T["show"]["keeps its content when the value stays truthy"] = function()
	run([[
		value, mounts = m.signal(1), 0
		view:render(m.show(value, function()
			mounts = mounts + 1
			return m.block("content")
		end))
		value(2)
		reactive.flush()
		value(3)
		reactive.flush()
	]])
	eq(child.lua_get("mounts"), 1)
end

T["show"]["content stays live after the condition reruns"] = function()
	run([[
		value, text = m.signal(1), m.signal("a")
		view:render(m.show(value, m.block(text)))
		value(2)
		reactive.flush()
		text("b")
		reactive.flush()
	]])
	eq(lines(), { "b" })
end

T["show"]["stops effects when unmounted"] = function()
	run([[
		open, count, runs = m.signal(true), m.signal(0), 0
		view:render(m.show(open, function()
			return m.block(function()
				runs = runs + 1
				return count()
			end)
		end))
		open(false)
		reactive.flush()
		count(1)
		reactive.flush()
	]])
	eq(child.lua_get("runs"), 1)
end

T["show"]["frees engine nodes when unmounted"] = function()
	run([[
		open = m.signal(false)
		view:render(m.show(open, m.block("a")))
		base = view.engine:node_count()
		for _ = 1, 20 do
			open(true)
			reactive.flush()
			open(false)
			reactive.flush()
		end
	]])
	eq(child.lua_get("view.engine:node_count() == base"), true)
end

T["show"]["relayouts through nested groups"] = function()
	run([[
		open = m.signal(false)
		local Inner = m.component(function()
			return m.show(open, m.block("inner"))
		end)
		local Outer = m.component(function()
			return Inner()
		end)
		view:render(m.block({ m.block("top"), Outer(), m.block("bottom") }))
		open(true)
		reactive.flush()
	]])
	eq(lines(), { "top", "inner", "bottom" })
end

T["show"]["nests"] = function()
	run([[
		outer, inner = m.signal(true), m.signal(false)
		view:render(m.block({
			m.show(outer, m.block({ m.block("a"), m.show(inner, m.block("b")) })),
			m.block("c"),
		}))
		inner(true)
		reactive.flush()
	]])
	eq(lines(), { "a", "b", "c" })

	run([[outer(false); reactive.flush()]])
	eq(lines(), { "c" })
end

T["each"] = new_set()

local function each_with(initial)
	run(([[
		mounts = 0
		items = m.signal(%s)
		view:render(m.block({
			m.block("head"),
			m.each(items, function(item)
				mounts = mounts + 1
				return m.block("row " .. item)
			end),
			m.block("tail"),
		}))
	]]):format(initial))
end

local function set_items(value)
	run(("items(%s); reactive.flush()"):format(value))
end

T["each"]["renders items in place"] = function()
	each_with("{ 1, 2 }")
	eq(lines(), { "head", "row 1", "row 2", "tail" })
end

local orders = {
	remove_first = { "{ 2, 3, 4 }", { 2, 3, 4 } },
	remove_middle = { "{ 1, 2, 4 }", { 1, 2, 4 } },
	remove_last = { "{ 1, 2, 3 }", { 1, 2, 3 } },
	insert_first = { "{ 9, 1, 2, 3, 4 }", { 9, 1, 2, 3, 4 } },
	insert_middle = { "{ 1, 2, 9, 3, 4 }", { 1, 2, 9, 3, 4 } },
	swap = { "{ 4, 2, 3, 1 }", { 4, 2, 3, 1 } },
	reverse = { "{ 4, 3, 2, 1 }", { 4, 3, 2, 1 } },
	rotate = { "{ 2, 3, 4, 1 }", { 2, 3, 4, 1 } },
	replace = { "{ 7, 8 }", { 7, 8 } },
	mixed = { "{ 4, 9, 2 }", { 4, 9, 2 } },
	empty = { "{}", {} },
}

for name, case in pairs(orders) do
	T["each"][name] = function()
		each_with("{ 1, 2, 3, 4 }")
		set_items(case[1])

		local expected = { "head" }
		for _, item in ipairs(case[2]) do
			expected[#expected + 1] = "row " .. item
		end
		expected[#expected + 1] = "tail"
		eq(lines(), expected)
	end
end

T["each"]["keeps the UI of items that stay"] = function()
	each_with("{ 1, 2, 3 }")
	set_items("{ 3, 1, 2, 4 }")
	eq(child.lua_get("mounts"), 4)
end

T["each"]["uses a key function"] = function()
	run([[
		local a, b = { id = 1, name = "a" }, { id = 2, name = "b" }
		items = m.signal({ a, b })
		view:render(m.each(items, function(item)
			return m.block(item.name)
		end, { key = function(item) return item.id end }))
		items({ { id = 2, name = "ignored" }, { id = 1, name = "ignored" } })
		reactive.flush()
	]])
	eq(lines(), { "b", "a" })
end

T["each"]["rejects duplicate keys"] = function()
	run([[
		errors = {}
		vim.notify = function(message) errors[#errors + 1] = message end
		items = m.signal({ 1 })
		view:render(m.each(items, function(item) return m.block(item) end))
		items({ 1, 1 })
		reactive.flush()
		vim.wait(10)
	]])
	eq(child.lua_get("errors[1]:find('twice') ~= nil"), true)
end

T["each"]["frees engine nodes of removed items"] = function()
	run([[
		items = m.signal({})
		view:render(m.each(items, function(item) return m.block(item) end))
		base = view.engine:node_count()
		for _ = 1, 10 do
			items({ 1, 2, 3 })
			reactive.flush()
			items({})
			reactive.flush()
		end
	]])
	eq(child.lua_get("view.engine:node_count() == base"), true)
end

T["press"] = new_set()

T["press"]["calls the handler under the cursor"] = function()
	run([[
		pressed = nil
		view:render(m.block({
			m.block("nothing"),
			m.button({ "press me", on_press = function() pressed = "button" end }),
		}))
		vim.api.nvim_win_set_cursor(0, { 2, 2 })
		handled = view:press()
	]])
	eq(child.lua_get("pressed"), "button")
	eq(child.lua_get("handled"), true)
end

T["press"]["reports when nothing was pressed"] = function()
	run([[
		view:render(m.block("nothing"))
		handled = view:press()
	]])
	eq(child.lua_get("handled"), false)
end

T["press"]["forgets handlers of unmounted nodes"] = function()
	run([[
		open = m.signal(true)
		view:render(m.show(open, m.button({ "x", on_press = function() end })))
		open(false)
		reactive.flush()
	]])
	eq(child.lua_get("vim.tbl_isempty(view.handlers)"), true)
end

T["updates match a fresh render"] = function()
	run([[
		-- Nested show, each and dynamic text, driven by random writes. After
		-- every flush the patched buffer must equal a new view of the same state.
		local seed = 12345
		local function rnd(n)
			seed = (seed * 16807) % 2147483647
			return seed % n + 1
		end

		local open, names, lists = {}, {}, {}
		for i = 1, 8 do
			open[i] = m.signal(i % 2 == 0)
			names[i] = m.signal("name" .. i)
			lists[i] = m.signal({ 1, 2, 3 })
		end

		local function Group(i)
			return m.block({
				m.inline("[" .. i .. "] ", "Label"),
				m.inline(names[i], i % 2 == 0 and "String" or "Number"),
				m.show(open[i], function()
					return m.block({
						margin_left = 2,
						m.each(lists[i], function(item)
							return m.block({ m.inline("item " .. item, "Comment") })
						end),
						i < 8 and Group(i + 1) or nil,
					})
				end),
			})
		end

		local function snapshot(target)
			local marks = vim.tbl_map(function(mark)
				return { mark[2], mark[3], mark[4].end_col, mark[4].hl_group }
			end, vim.api.nvim_buf_get_extmarks(target.win.buf, target.ns, 0, -1, { details = true }))
			table.sort(marks, function(a, b)
				if a[1] ~= b[1] then return a[1] < b[1] end
				if a[2] ~= b[2] then return a[2] < b[2] end
				return a[4] < b[4]
			end)
			return vim.inspect({ vim.api.nvim_buf_get_lines(target.win.buf, 0, -1, false), marks })
		end

		local function fresh()
			local buf = vim.api.nvim_create_buf(false, true)
			local other = Markup.window({ buf = buf, position = "float", show = true, enter = false, width = 40, height = 5 })
			local target = Markup.view(other)
			target.commands:resize(vim.api.nvim_win_get_width(win.win))
			target:render(Group(1))
			local result = snapshot(target)
			target:unmount()
			reactive.flush()
			other:close()
			return result
		end

		view:render(Group(1))
		failures, steps = {}, 0
		for step = 1, 250 do
			local i = rnd(8)
			local action = rnd(4)
			if action == 1 then
				open[i](function(value) return not value end)
			elseif action == 2 then
				names[i](("x"):rep(rnd(9)))
			elseif action == 3 then
				local items = {}
				for _ = 1, rnd(5) do
					local value = rnd(7)
					if not vim.tbl_contains(items, value) then
						items[#items + 1] = value
					end
				end
				lists[i](items)
			else
				lists[i]({})
			end
			reactive.flush()
			steps = step
			if snapshot(view) ~= fresh() then
				failures[#failures + 1] = step
				break
			end
		end
	]])
	eq(child.lua_get("failures"), {})
	eq(child.lua_get("steps"), 250)
end

T["lifecycle"] = new_set()

T["lifecycle"]["rendering again replaces everything"] = function()
	run([[
		count, runs = m.signal(0), 0
		view:render(m.block(function()
			runs = runs + 1
			return count()
		end))
		view:render(m.block("new"))
		count(1)
		reactive.flush()
	]])
	eq(lines(), { "new" })
	eq(child.lua_get("runs"), 1)
end

T["lifecycle"]["follows the window width"] = function()
	run([[
		view:render(m.block({ m.block({ "a", style = "Label" }) }))
		view.commands:resize(10)
		view:request_commit()
		reactive.flush()
	]])
	eq(marks()[1][3], 10)
end

T["lifecycle"]["holds more nodes than mlua has handles"] = function()
	run([[
		local rows = {}
		for i = 1, 20000 do
			rows[i] = m.block({ m.inline("row ", "Label"), m.inline(i, "Number") })
		end
		view:render(m.block(rows))
	]])
	eq(child.lua_get("vim.api.nvim_buf_line_count(win.buf)"), 20000)
end

return T
