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

T["white_space"] = new_set()

T["white_space"]["wraps text in a block by default"] = function()
	run([[view:render(m.block({ width = 10, "the quick brown fox" }))]])
	eq(lines(), { "the quick", "brown fox" })
end

T["white_space"]["nowrap keeps one line"] = function()
	run([[view:render(m.block({ width = 5, white_space = "nowrap", m.inline("the quick brown fox") }))]])
	eq(lines(), { "the quick brown fox" })
end

T["white_space"]["children inherit it"] = function()
	run([[view:render(m.block({
		width = 5, white_space = "nowrap",
		m.block("aaaa bbbb"),
		m.block({ white_space = "normal", "cccc dddd" }),
	}))]])
	eq(lines(), { "aaaa bbbb", "cccc", "dddd" })
end

T["white_space"]["follows a signal"] = function()
	run([[
		mode = m.signal("normal")
		view:render(m.block({ width = 5, white_space = mode, m.block("aaaa bbbb") }))
		mode("nowrap")
		reactive.flush()
	]])
	eq(lines(), { "aaaa bbbb" })

	run([[mode("normal"); reactive.flush()]])
	eq(lines(), { "aaaa", "bbbb" })
end

T["white_space"]["rejects unknown values"] = function()
	expect.error(function()
		run([[view:render(m.block({ white_space = "pre-line", "x" }))]])
	end, "invalid white_space")
end

T["white_space"]["highlights follow their text across lines"] = function()
	run([[view:render(m.block({
		width = 8,
		m.inline("aaa ", "Label"),
		m.inline("bbb ccc", "String"),
	}))]])
	eq(lines(), { "aaa bbb", "ccc" })
	eq(marks(), { { 0, 0, 4, "Label" }, { 0, 4, 7, "String" }, { 1, 0, 3, "String" } })
end

T["white_space"]["measures wide characters"] = function()
	run([[view:render(m.block({ width = 4, "你好世界" }))]])
	eq(lines(), { "你好", "世界" })
end

T["white_space"]["respects ambiwidth"] = function()
	run([[
		vim.o.ambiwidth = "double"
		view:render(m.block({ width = 4, "≤≤≤≤" }))
	]])
	eq(lines(), { "≤≤", "≤≤" })
end

T["white_space"]["pushes following content down"] = function()
	run([[view:render(m.block({ m.block({ width = 5, "aaaa bbbb" }), m.block("next") }))]])
	eq(lines(), { "aaaa", "bbbb", "next" })
end

T["white_space"]["rewraps when the text changes at the same width"] = function()
	run([[
		value = m.signal("aaaa bbbb")
		view:render(m.block({ width = 5, value }))
		value("aa bb cc ")
		reactive.flush()
	]])
	eq(lines(), { "aa bb", "cc" })
end

T["white_space"]["rewraps when the window resizes"] = function()
	run([[
		view:render(m.block({ m.block("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb") }))
	]])
	eq(#lines(), 2)

	run([[
		view.commands:resize(20)
		view:request_commit()
		reactive.flush()
	]])
	eq(#lines(), 4)
end

T["white_space"]["honours newlines"] = function()
	run([[view:render(m.block({ m.block("one\ntwo"), m.block({ white_space = "nowrap", "three\nfour" }) }))]])
	eq(lines(), { "one", "two", "three", "four" })
end

T["white_space"]["wraps inside flex and grid"] = function()
	run([[view:render(m.flex({
		width = 12,
		m.block({ "aaaa bbbb cccc", shrink = 1 }),
		m.block({ "side", shrink = 0 }),
	}))]])
	eq(lines(), { "aaaa    side", "bbbb", "cccc" })

	run([[view:render(m.grid({ columns = { 5, 5 }, m.block("aaaa bbbb"), m.block("c") }))]])
	eq(lines(), { "aaaa c", "bbbb" })
end

T["white_space"]["presses work on every line of a span"] = function()
	run([[
		pressed = nil
		view:render(m.block({
			width = 6,
			m.inline({ "aaaa bbbb", on_press = function() pressed = true end }),
		}))
		vim.api.nvim_win_set_cursor(0, { 2, 1 })
		view:press()
	]])
	eq(child.lua_get("pressed"), true)
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

T["hidden windows"] = new_set()

T["hidden windows"]["fill when they open"] = function()
	run([[
		hidden = Markup.window({ position = "float", show = false, width = 30, height = 5, enter = false })
		later = Markup.view(hidden)
		text = m.signal("first")
		later:render(m.block(text))
		text("second")
		reactive.flush()
		hidden:show()
		reactive.flush()
	]])
	eq(child.lua_get("vim.api.nvim_buf_get_lines(hidden.buf, 0, -1, false)")[1]:gsub("%s+$", ""), "second")
end

T["hidden windows"]["lay out at the real width once open"] = function()
	run([[
		hidden = Markup.window({ position = "float", show = false, width = 30, height = 5, enter = false })
		later = Markup.view(hidden)
		later:render(m.block({ "x", style = "Label" }))
		hidden:show()
		reactive.flush()
	]])
	eq(child.lua_get("later.engine:describe(1).outer_width"), 30)
end

T["hidden windows"]["fill again when reopened"] = function()
	run([[
		hidden = Markup.window({ position = "float", show = false, width = 30, height = 5, enter = false })
		later = Markup.view(hidden)
		later:render(m.block("content"))
		hidden:show()
		reactive.flush()
		hidden:hide()
		hidden:show()
		reactive.flush()
	]])
	eq(child.lua_get("vim.api.nvim_buf_get_lines(hidden.buf, 0, -1, false)")[1]:gsub("%s+$", ""), "content")
end

T["hooks"] = new_set()

T["hooks"]["use_view returns the view"] = function()
	run([[
		local Comp = m.component(function()
			found = m.use_view() == view
			return m.block("x")
		end)
		view:render(Comp())
	]])
	eq(child.lua_get("found"), true)
end

T["hooks"]["use_key lives as long as the component"] = function()
	run([[
		open, pressed = m.signal(true), 0
		local Comp = m.component(function()
			m.use_key("x", function() pressed = pressed + 1 end)
			return m.block("x")
		end)
		view:render(m.show(open, function() return Comp() end))
	]])
	child.type_keys("x")
	eq(child.lua_get("pressed"), 1)

	run([[open(false); reactive.flush()]])
	child.type_keys("x")
	eq(child.lua_get("pressed"), 1)
end

T["hooks"]["a remounted key replaces the old one"] = function()
	run([[
		page, last = m.signal("a"), nil
		local function Page(name)
			return m.component(function()
				m.use_key("k", function() last = name end)
				return m.block(name)
			end)()
		end
		view:render(m.block(function()
			return Page(page())
		end))
		page("b")
		reactive.flush()
	]])
	child.type_keys("k")
	eq(child.lua_get("last"), "b")
end

T["snap"] = new_set()

local function snap_view()
	run([[
		view = Markup.view(win, { snap = true })
		pressed = nil
		local function item(name)
			return m.block({ name, width = "fit", on_press = function() pressed = name end })
		end
		view:render(m.block({
			m.block("title"),
			m.block(""),
			item("one"),
			m.block(""),
			item("two"),
		}))
		vim.api.nvim_win_set_cursor(0, { 3, 0 })
		view.cursor = { 2, 0 }
	]])
end

T["snap"]["jumps between interactive rows"] = function()
	snap_view()
	child.type_keys("j")
	eq(child.lua_get("vim.api.nvim_win_get_cursor(0)")[1], 5)

	child.type_keys("k")
	eq(child.lua_get("vim.api.nvim_win_get_cursor(0)")[1], 3)
end

T["snap"]["stays put at the end"] = function()
	snap_view()
	child.type_keys("k")
	eq(child.lua_get("vim.api.nvim_win_get_cursor(0)")[1], 3)
end

local function tall_view()
	run([[
		view = Markup.view(win, { snap = true })
		local rows = {
			m.block({ on_press = function() end, "button one" }),
			m.block({ on_press = function() end, "button two" }),
		}
		for i = 1, 60 do rows[#rows + 1] = m.block("text " .. i) end
		view:render(m.block(rows))
		reactive.flush()
		vim.api.nvim_win_set_cursor(0, { 2, 0 })
		view.cursor = { 1, 0 }
		height = vim.api.nvim_win_get_height(0)
	]])
end

local function top_line()
	return child.lua_get("vim.fn.line('w0')")
end

T["snap"]["j past the last button scrolls to what is below"] = function()
	tall_view()
	child.type_keys("j")
	eq(top_line(), 2)
	child.type_keys("j")
	eq(top_line(), 3)
end

T["snap"]["the whole page can be reached"] = function()
	tall_view()
	for _ = 1, 80 do
		child.type_keys("j")
	end
	eq(child.lua_get("vim.fn.line('w$')"), 62)
end

T["snap"]["k comes back to the buttons"] = function()
	tall_view()
	for _ = 1, 30 do
		child.type_keys("j")
	end
	for _ = 1, 80 do
		child.type_keys("k")
	end
	eq(top_line(), 1)
	eq(child.lua_get("vim.api.nvim_win_get_cursor(0)[1] <= 2"), true)
end

T["snap"]["scrolling is not undone"] = function()
	tall_view()
	child.type_keys("<C-e>", "<C-e>", "<C-e>", "<C-e>")
	eq(top_line(), 5)
	child.type_keys("<C-d>")
	eq(top_line() > 5, true)
end

T["snap"]["scrolls with the scrolloff people use"] = function()
	child.o.scrolloff = 8
	tall_view()
	for _ = 1, 80 do
		child.type_keys("j")
	end
	eq(child.lua_get("vim.fn.line('w$')"), 62)

	for _ = 1, 80 do
		child.type_keys("k")
	end
	eq(top_line(), 1)
end

T["snap"]["scrolling sticks with scrolloff"] = function()
	child.o.scrolloff = 8
	tall_view()
	child.type_keys("<C-e>", "<C-e>", "<C-e>", "<C-e>")
	eq(top_line(), 5)
end

T["snap"]["leaves the global scrolloff alone"] = function()
	child.o.scrolloff = 8
	tall_view()
	-- `vim.o` reads the value in effect here, so the global one comes from `vim.go`.
	eq(child.lua_get("vim.go.scrolloff"), 8)
	eq(child.lua_get("vim.api.nvim_get_option_value('scrolloff', { scope = 'local', win = win.win })"), 0)

	-- Another window still has the global value.
	child.cmd("vnew")
	eq(child.lua_get("vim.o.scrolloff"), 8)
end

T["snap"]["a page that fits does not scroll"] = function()
	snap_view()
	child.type_keys("j", "j", "j")
	eq(top_line(), 1)
end

T["snap"]["text mode stops on text and buttons only"] = function()
	child.lua([[
		view = Markup.view(win, { snap = "text" })
		view:render(m.block({
			padding = { 1, 2 },
			m.block("one"),
			m.block({ margin_top = 1, border = "half", style = "Visual", "two" }),
			m.block({ margin_top = 1, on_press = function() end, "button" }),
		}))
		reactive.flush()
		vim.api.nvim_win_set_cursor(win.win, { 2, 2 })
		view.cursor = nil
		view:snap_cursor()
	]])

	local function row_text()
		return child.lua_get("vim.trim(vim.api.nvim_get_current_line())")
	end

	eq(row_text(), "one")
	child.type_keys("j")
	eq(row_text(), "two")
	child.type_keys("j")
	eq(row_text(), "button")
	child.type_keys("j")
	eq(row_text(), "button")
	child.type_keys("gg")
	eq(row_text(), "one")
	child.type_keys("G")
	eq(row_text(), "button")
end

T["hide_cursor"] = new_set()

local function hidden()
	return child.lua_get("vim.o.guicursor:find('MarkupHiddenCursor', 1, true) ~= nil")
end

local function hiding_view()
	child.lua([[
		original = vim.o.guicursor
		view = Markup.view(win, { hide_cursor = true })
		view:render(m.block("x"))
		reactive.flush()
	]])
end

T["hide_cursor"]["hides it only in normal mode"] = function()
	hiding_view()
	eq(hidden(), true)
	eq(child.lua_get("vim.o.guicursor:find(',n:MarkupHiddenCursor$') ~= nil"), true)
	eq(child.lua_get("vim.api.nvim_get_hl(0, { name = 'MarkupHiddenCursor' }).blend"), 100)
end

T["hide_cursor"]["comes back when leaving the window"] = function()
	hiding_view()
	child.cmd("vnew")
	eq(child.lua_get("vim.o.guicursor == original"), true)

	child.cmd("wincmd p")
	eq(hidden(), true)
end

T["hide_cursor"]["comes back when changing tabs"] = function()
	hiding_view()
	child.cmd("tabnew")
	eq(child.lua_get("vim.o.guicursor == original"), true)

	child.cmd("tabprevious")
	eq(hidden(), true)
end

T["hide_cursor"]["comes back with the view gone"] = function()
	hiding_view()
	child.lua("view:destroy()")
	eq(child.lua_get("vim.o.guicursor == original"), true)
end

T["hide_cursor"]["stays hidden between two hiding views"] = function()
	child.lua([[
		original = vim.o.guicursor
		first = Markup.view(win, { hide_cursor = true })
		first:render(m.block("first"))
		reactive.flush()
		vim.cmd("vsplit")
		vim.cmd("enew")
		other = Markup.window({ position = "current", hijack = true, show = false, minimal = false })
		other.buf = vim.api.nvim_get_current_buf()
		other:show()
		second = Markup.view(other, { hide_cursor = true })
		second:render(m.block("second"))
		reactive.flush()
	]])
	for _ = 1, 4 do
		child.cmd("wincmd p")
		eq(hidden(), true)
	end
	child.cmd("new")
	eq(child.lua_get("vim.o.guicursor == original"), true)
end

T["hide_cursor"]["stays out of other views"] = function()
	child.lua([[
		original = vim.o.guicursor
		view = Markup.view(win)
		view:render(m.block("x"))
		reactive.flush()
	]])
	eq(child.lua_get("vim.o.guicursor == original"), true)
end

T["click"] = new_set()

local function click_view(mode)
	child.lua(([[
		pressed = nil
		view = Markup.view(win, { click = %s })
		local function button(name)
			return m.block({ name, width = "fit", on_press = function() pressed = name end })
		end
		view:render(m.block({ m.block("title"), button("one"), m.block(""), button("two") }))
		reactive.flush()
	]]):format(mode == false and "false" or mode and ("%q"):format(mode) or "nil"))
end

--- Clicks a cell of the buffer, from zero, wherever its window is: twice, unless
--- told otherwise.
local function click(row, col, times)
	local screen = child.lua_get(("vim.fn.screenpos(win.win, %d, %d)"):format(row + 1, col + 1))
	for _ = 1, times or 2 do
		child.api.nvim_input_mouse("left", "press", "", 0, screen.row - 1, screen.col - 1)
		child.api.nvim_input_mouse("left", "release", "", 0, screen.row - 1, screen.col - 1)
	end
	child.lua("vim.wait(20, function() return false end, 5)")
end

T["click"]["a single click presses by default"] = function()
	click_view()
	click(3, 1, 1)
	eq(child.lua_get("pressed"), "two")
	click(1, 0, 1)
	eq(child.lua_get("pressed"), "one")
end

T["click"]["anything else stays a click"] = function()
	click_view()
	click(0, 2, 1)
	eq(child.lua_get("pressed"), vim.NIL)
	eq(child.lua_get("vim.api.nvim_win_get_cursor(0)[1]"), 1)
end

T["click"]["a single click reaches a window without the focus"] = function()
	click_view()
	child.cmd("vnew")
	click(3, 1, 1)
	eq(child.lua_get("pressed"), "two")
end

T["click"]["with double, a single click only moves the cursor"] = function()
	click_view("double")
	click(3, 1, 1)
	eq(child.lua_get("pressed"), vim.NIL)
	eq(child.lua_get("vim.api.nvim_win_get_cursor(0)[1]"), 4)
end

T["click"]["with double, a double click presses and selects nothing"] = function()
	click_view("double")
	click(3, 1, 2)
	eq(child.lua_get("pressed"), "two")
	eq(child.fn.mode(), "n")
end

T["click"]["can be turned off"] = function()
	click_view(false)
	click(3, 1, 1)
	click(3, 1, 2)
	eq(child.lua_get("pressed"), vim.NIL)
end

T["click"]["picks a row of the picker"] = function()
	child.lua([[
		picked = nil
		local items = {}
		for i, name in ipairs({ "first", "second", "third" }) do items[i] = { label = name, value = name } end
		Markup.picker({ items = items, on_select = function(value) picked = value end })
		reactive.flush()
		for _, w in ipairs(vim.api.nvim_list_wins()) do
			local config = vim.api.nvim_win_get_config(w)
			if config.relative ~= "" and w ~= vim.api.nvim_get_current_win() then list = w end
		end
	]])
	-- Without a UI Neovim sends clicks past floats, so this hands the view what
	-- a click on the second row gives.
	child.lua([[
		for view in pairs(Markup.views) do
			if view.win.win == list then view:click({ line = 2, wincol = 3 }) end
		end
		vim.wait(20, function() return false end, 5)
	]])
	eq(child.lua_get("picked"), "second")
end

T["snap"]["presses land on the snapped node"] = function()
	snap_view()
	child.type_keys("j")
	run("view:press()")
	eq(child.lua_get("pressed"), "two")
end

T["wide text"] = new_set()

--- Display width of every row, which must all reach the same column in a card.
local function row_widths()
	return child.lua_get([[vim.tbl_map(function(line)
		return vim.fn.strdisplaywidth(line)
	end, vim.api.nvim_buf_get_lines(win.buf, 0, -1, false))]])
end

--- Text covered by each highlight, read back from the buffer.
local function marked_text()
	return child.lua_get([[vim.tbl_map(function(mark)
		local line = vim.api.nvim_buf_get_lines(win.buf, mark[2], mark[2] + 1, false)[1]
		return { mark[4].hl_group, line:sub(mark[3] + 1, mark[4].end_col) }
	end, vim.api.nvim_buf_get_extmarks(win.buf, view.ns, 0, -1, { details = true }))]])
end

local samples = {
	ascii = "plain text",
	chinese = "你好世界",
	mixed = "ab你好cd",
	icon = "\u{f07b} folder",
	tab = "\tindented",
	tab_box = "\t│ Input",
	emoji = "😀 ok",
	accents = "café",
}

for name, sample in pairs(samples) do
	T["wide text"]["card rows line up with " .. name] = function()
		child.lua(([[
			view:render(m.block({
				m.block({ width = 30, style = "Visual", m.block("short"), m.block(%q), m.block("end") }),
			}))
		]]):format(sample))
		eq(row_widths(), { 30, 30, 30 })
	end
end

T["wide text"]["highlights cover exactly their own text"] = function()
	run([[view:render(m.block({
		m.inline("你好", "Label"),
		m.inline("\u{f07b} ", "String"),
		m.inline("世界", "Number"),
		m.inline("ab", "Comment"),
	}))]])
	eq(marked_text(), {
		{ "Label", "你好" },
		{ "String", "\u{f07b} " },
		{ "Number", "世界" },
		{ "Comment", "ab" },
	})
end

T["wide text"]["a parent highlight spans mixed text exactly"] = function()
	run([[view:render(m.block({
		m.inline("x"),
		m.inline({ "你a好b", style = "Label" }),
		m.inline("y"),
	}))]])
	eq(marked_text(), { { "Label", "你a好b" } })
end

T["wide text"]["wraps chinese at the block width"] = function()
	run([[view:render(m.block({ width = 7, "你好世界你好" }))]])
	eq(lines(), { "你好世", "界你好" })
end

T["wide text"]["wraps icons with words"] = function()
	run([[view:render(m.block({ width = 8, "\u{f07b} folder \u{f15b} file" }))]])
	eq(lines(), { "\u{f07b} folder", "\u{f15b} file" })
end

T["wide text"]["overlays cut through wide text cleanly"] = function()
	run([[view:render(m.block({
		m.block("你好世界"),
		m.block({ "X", position = "absolute", top = 0, left = 2 }),
	}))]])
	eq(lines(), { "你X 世界" })
	eq(row_widths()[1], 8)
end

T["wide text"]["overlays keep mixed text they do not touch"] = function()
	run([[view:render(m.block({
		m.block("ab你好cd"),
		m.block({ "X", position = "absolute", top = 0, left = 6 }),
	}))]])
	eq(lines(), { "ab你好Xd" })
end

T["wide text"]["follows ambiwidth"] = function()
	run([[
		vim.o.ambiwidth = "double"
		view:render(m.block({ width = 10, style = "Visual", m.block("≤≤") }))
	]])
	eq(row_widths(), { 10 })
end

T["wide text"]["follows setcellwidths"] = function()
	run([[
		view:render(m.block({ width = 4, "\u{f07b}\u{f07b}\u{f07b}\u{f07b}\u{f07b}" }))
		first = lines()
		vim.fn.setcellwidths({ { 0xf07b, 0xf07b, 2 } })
		view:render(m.block({ width = 4, "\u{f07b}\u{f07b}\u{f07b}\u{f07b}\u{f07b}" }))
	]])
	eq(lines(), { "\u{f07b}\u{f07b}", "\u{f07b}\u{f07b}", "\u{f07b}" })
end

T["wide text"]["updates keep rows aligned"] = function()
	run([[
		name = m.signal("ab")
		view:render(m.block({ m.block({ width = 12, style = "Visual", m.block(name) }) }))
		name("你好\t世界")
		reactive.flush()
	]])
	eq(row_widths(), { 12 })
end

T["border"] = new_set()

T["border"]["draws the presets"] = function()
	run([[view:render(m.block({ m.block({ "ab", width = 4, border = "rounded" }) }))]])
	eq(lines(), { "╭────╮", "│ab  │", "╰────╯" })

	run([[view:render(m.block({ m.block({ "ab", width = 2, border = "double" }) }))]])
	eq(lines(), { "╔══╗", "║ab║", "╚══╝" })
end

T["border"]["draws chosen sides"] = function()
	run([[view:render(m.block({ m.block({ "ab", width = 2, border = "single", border_sides = { "top" } }) }))]])
	eq(lines(), { "──", "ab" })
end

T["border"]["takes custom characters"] = function()
	run([[view:render(m.block({ m.block({ "a", width = 1, border = { chars = "+-+|+-+|" } }) }))]])
	eq(lines(), { "+-+", "|a|", "+-+" })
end

T["border"]["uses border_style"] = function()
	run([[view:render(m.block({ m.block({ "a", width = 1, border = "single", border_style = "Label" }) }))]])
	eq(marks()[1][4], "Label")
end

T["border"]["works in flex and wraps inside"] = function()
	run([[view:render(m.flex({
		width = 12, gap = 1,
		m.block({ "aaaa bbbb", border = "single", grow = 1 }),
		m.block({ "x", border = "single", shrink = 0 }),
	}))]])
	eq(lines(), { "┌──────┐ ┌─┐", "│aaaa  │ │x│", "│bbbb  │ │ │", "└──────┘ └─┘" })
end

T["border"]["presses stay inside"] = function()
	run([[
		pressed = nil
		view:render(m.block({ m.block({ "ab", width = 2, border = "single", on_press = function() pressed = true end }) }))
		vim.api.nvim_win_set_cursor(0, { 2, 1 })
		view:press()
	]])
	eq(child.lua_get("pressed"), true)
end

T["border"]["rejects unknown values"] = function()
	expect.error(function()
		run([[view:render(m.block({ "x", border = "wavy" }))]])
	end, "invalid border")
	expect.error(function()
		run([[view:render(m.block({ "x", border = "single", border_sides = { "up" } }))]])
	end, "invalid border side")
end

T["border"]["half uses half blocks in the color of the background"] = function()
	run([[
		vim.api.nvim_set_hl(0, "Card", { bg = "#123456" })
		view:render(m.block({ m.block({ "ab", width = 4, padding = { 0, 1 }, style = "Card", border = "half" }) }))
	]])
	eq(lines(), { "▄▄▄▄▄▄", " ab", "▀▀▀▀▀▀" })

	local groups = marks()
	eq(groups[1][4], "MarkupEdge_Card")
	eq(child.lua_get("vim.api.nvim_get_hl(0, { name = 'MarkupEdge_Card' }).fg"), 0x123456)
	eq(child.lua_get("vim.api.nvim_get_hl(0, { name = 'MarkupEdge_Card' }).bg"), vim.NIL)
end

T["border"]["half keeps the background off its rows"] = function()
	run([[
		vim.api.nvim_set_hl(0, "Card", { bg = "#123456" })
		view:render(m.block({ m.block({ "ab", width = 2, style = "Card", border = "half" }) }))
	]])
	local rows = {}
	for _, mark in ipairs(marks()) do
		rows[mark[4]] = rows[mark[4]] or {}
		table.insert(rows[mark[4]], mark[1])
	end
	eq(rows["Card"], { 1 })
	eq(rows["MarkupEdge_Card"], { 0, 2 })
end

T["border"]["half follows the colorscheme"] = function()
	run([[
		vim.api.nvim_set_hl(0, "Card", { bg = "#123456" })
		view:render(m.block({ "x", style = "Card", border = "half" }))
		vim.api.nvim_set_hl(0, "Card", { bg = "#654321" })
		vim.api.nvim_exec_autocmds("ColorScheme", {})
	]])
	eq(child.lua_get("vim.api.nvim_get_hl(0, { name = 'MarkupEdge_Card' }).fg"), 0x654321)
end

T["border"]["fixed elements keep their border"] = function()
	run([[
		vim.api.nvim_set_hl(0, "Card", { bg = "#123456" })
		view:render(m.block({
			m.block({ "pinned", position = "fixed", style = "Card", border = "half" }),
			m.block("body"),
		}))
		reactive.flush()
		band = view.fixed[1]
	]])
	eq(child.lua_get("vim.trim(vim.api.nvim_buf_get_lines(band.win.buf, 0, 1, false)[1]):sub(1, 3)"), "▄")
	eq(child.lua_get("vim.api.nvim_win_get_height(band.win.win)"), 3)
	eq(lines(), { "", "", "", "body" })
end

T["fixed"] = new_set()

local function fixed_view()
	run([[
		title = m.signal("title")
		rows = {}
		for i = 1, 100 do
			rows[i] = m.block("row " .. i)
		end
		view:render(m.block({
			m.block({ title, position = "fixed", top = 0, padding = { 1, 0 }, style = "Visual" }),
			rows,
		}))
		reactive.flush()
		band = view.fixed[1]
	]])
end

local function band_lines()
	return child.lua_get("vim.tbl_map(vim.trim, vim.api.nvim_buf_get_lines(band.win.buf, 0, -1, false))")
end

local function overlay_view()
	child.lua([[
		visible = m.signal(false)
		rows = {}
		for i = 1, 40 do rows[i] = m.block("row " .. i) end
		view:render(m.block({
			m.block({ "band", position = "fixed", top = 0 }),
			m.block({
				position = "fixed",
				overlay = true,
				m.show(visible, function() return m.block("note") end),
			}),
			m.block(rows),
		}))
		reactive.flush()
		band, note = view.fixed[1], view.fixed[2]
	]])
end

T["fixed"]["an overlay stacks below and reserves nothing"] = function()
	overlay_view()
	child.lua([[
		before = vim.api.nvim_buf_get_lines(win.buf, 0, 3, false)
		visible(true)
		reactive.flush()
		reactive.flush()
	]])
	eq(child.lua_get("vim.api.nvim_buf_get_lines(win.buf, 0, 3, false)"), child.lua_get("before"))
	eq(child.lua_get("vim.api.nvim_win_get_config(note.win.win).row"), 1)
	eq(child.lua_get("vim.api.nvim_win_get_config(note.win.win).hide"), false)
end

T["fixed"]["an empty overlay stays out of sight"] = function()
	overlay_view()
	eq(child.lua_get("vim.api.nvim_win_get_config(note.win.win).hide"), true)

	child.lua("visible(true); reactive.flush(); reactive.flush(); visible(false); reactive.flush(); reactive.flush()")
	eq(child.lua_get("vim.api.nvim_win_get_config(note.win.win).hide"), true)
end

T["fixed"]["the width can be tracked"] = function()
	overlay_view()
	child.lua([[
		seen = {}
		reactive.effect(function() seen[#seen + 1] = view:columns() end)
		vim.cmd("vnew")
		vim.api.nvim_win_set_width(win.win, 30)
	]])
	-- WinResized fires from the main loop, once the call above returned.
	child.lua("vim.wait(20, function() return false end, 5)")
	child.lua("reactive.flush()")
	eq(child.lua_get("seen[1] > 30"), true)
	eq(child.lua_get("seen[#seen]"), 30)
end

T["fixed"]["the width is known once a hidden window opens"] = function()
	child.lua([[
		vim.cmd("vnew")
		hidden = Markup.window({ position = "right", width = 30, show = false, enter = false })
		late = Markup.view(hidden)
		late:render(m.block("x"))
		reactive.flush()
		hidden:show()
		reactive.flush()
	]])
	eq(child.lua_get("late:columns()"), child.lua_get("vim.api.nvim_win_get_width(hidden.win)"))
end

T["fixed"]["scrolling can be tracked"] = function()
	overlay_view()
	child.lua([[
		seen = {}
		reactive.effect(function() seen[#seen + 1] = view:scroll() end)
		vim.api.nvim_win_set_cursor(win.win, { 6, 0 })
		vim.cmd("normal! zt")
		view:update_scroll()
	]])
	eq(child.lua_get("seen[#seen]"), 5)
end

T["fixed"]["renders in a float over the window"] = function()
	fixed_view()
	eq(band_lines(), { "", "title", "" })
	eq(child.lua_get("vim.api.nvim_win_get_config(band.win.win).relative"), "win")
	eq(child.lua_get("vim.api.nvim_win_get_height(band.win.win)"), 3)
end

T["fixed"]["reserves its rows in the buffer"] = function()
	fixed_view()
	eq(vim.list_slice(lines(), 1, 4), { "", "", "", "row 1" })
end

T["fixed"]["stays put while the buffer scrolls"] = function()
	fixed_view()
	run([[
		vim.cmd("normal! 50Gzt")
		vim.cmd("redraw")
		row = vim.api.nvim_win_get_config(band.win.win).row
	]])
	eq(child.lua_get("row"), 0)
	eq(child.lua_get("vim.fn.line('w0') > 1"), true)
	eq(child.get_screenshot().text[2][1] ~= nil, true)
end

T["fixed"]["colors the whole band"] = function()
	fixed_view()
	eq(child.lua_get("vim.wo[band.win.win].winhighlight"), "Normal:Visual")
end

T["fixed"]["cannot take the cursor"] = function()
	fixed_view()
	eq(child.lua_get("vim.api.nvim_win_get_config(band.win.win).focusable"), false)
end

T["fixed"]["updates with signals"] = function()
	fixed_view()
	run([[title("changed"); reactive.flush()]])
	eq(band_lines()[2], "changed")
end

T["fixed"]["follows the height of its content"] = function()
	run([[
		extra = m.signal(false)
		view:render(m.block({
			m.block({ position = "fixed", m.block("a"), m.show(extra, m.block("b")) }),
			m.block("content"),
		}))
		reactive.flush()
		band = view.fixed[1]
	]])
	eq(lines(), { "", "content" })

	run([[extra(true); reactive.flush(); reactive.flush()]])
	eq(child.lua_get("vim.api.nvim_win_get_height(band.win.win)"), 2)
	eq(lines(), { "", "", "content" })
end

T["fixed"]["follows the width of the window"] = function()
	fixed_view()
	run([[
		vim.cmd("vsplit")
		vim.wait(200, function()
			reactive.flush()
			return vim.api.nvim_win_get_width(band.win.win) == vim.api.nvim_win_get_width(win.win)
		end, 10)
	]])
	eq(child.lua_get("vim.api.nvim_win_get_width(band.win.win) == vim.api.nvim_win_get_width(win.win)"), true)
end

T["fixed"]["closes and reopens with its window"] = function()
	run([[
		host = Markup.window({ position = "right", enter = false, show = true, width = 0.4 })
		hosted = Markup.view(host)
		hosted:render(m.block({ m.block({ "pinned", position = "fixed" }), m.block("body") }))
		reactive.flush()
		band = hosted.fixed[1]
		host:hide()
		vim.wait(50, function() return not band.win:win_valid() end, 5)
	]])
	eq(child.lua_get("not band.win:win_valid()"), true)

	run([[host:show(); reactive.flush()]])
	eq(child.lua_get("band.win:win_valid() and true"), true)
	eq(band_lines()[1], "pinned")
end

T["fixed"]["goes away with its element"] = function()
	run([[
		open = m.signal(true)
		view:render(m.block({
			m.show(open, m.block({ "pinned", position = "fixed" })),
			m.block("body"),
		}))
		reactive.flush()
		band = view.fixed[1]
		before = #vim.api.nvim_tabpage_list_wins(0)
		open(false)
		reactive.flush()
	]])
	eq(child.lua_get("#view.fixed"), 0)
	eq(child.lua_get("#vim.api.nvim_tabpage_list_wins(0) == before - 1"), true)
	eq(lines(), { "body" })
end

T["fixed"]["leaves the inspector alone"] = function()
	fixed_view()
	eq(child.lua_get("Markup.view.find(win.win) == view"), true)
	eq(child.lua_get("band.view.devtool"), true)
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
