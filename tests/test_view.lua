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
		run([[view:render(m.flex({ m.block("a") }))]])
	end, "not implemented")
end

T["highlights"] = new_set()

local function marks()
	return child.lua_get([[vim.tbl_map(function(mark)
		return { mark[2], mark[3], mark[4].end_col, mark[4].hl_group }
	end, vim.api.nvim_buf_get_extmarks(win.buf, view.ns, 0, -1, { details = true }))]])
end

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
