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

T["static"]["max width constrains wrapping and the measured height"] = function()
	run([[view:render(m.block({ max_width = 5, "aa bb cc" }))]])
	eq(lines(), { "aa bb", "cc" })
	eq(child.lua_get("view.engine:describe(2).outer_height"), 2)
end

T["static"]["full height uses the definite height of the parent block"] = function()
	run(
		[[view:render(m.block({ height = 3, m.block({height = "full", "first"}), m.block("next") }))]]
	)
	eq(lines(), { "first", "", "", "next" })
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

-- The props docs promise every value can be a function. Found by
-- tests/test_fuzz.lua, which made these dynamic and saw the mount fail.
T["shorthands"] = new_set()

T["shorthands"]["padding can follow a signal"] = function()
	run([[
		padding = m.signal({ 0, 2 })
		view:render(m.block({ m.block({ "a", padding = padding }) }))
		first = lines()
		padding({ 1, 0, 0, 3 })
		reactive.flush()
	]])
	eq(child.lua_get("first"), { "  a" })
	eq(lines(), { "", "   a" })
end

T["shorthands"]["margin can follow a signal"] = function()
	run([[
		margin = m.signal(0)
		view:render(m.block({ m.block({ "a", margin = margin }) }))
		margin({ 1, 4 })
		reactive.flush()
	]])
	eq(lines(), { "", "    a", "" })
end

T["shorthands"]["inset can follow a signal"] = function()
	run([[
		local function ui(inset)
			return m.block({ m.block("....."), m.block({ "X", position = "absolute", inset = inset }) })
		end
		view:render(ui({ 0, 0, 0, 3 }))
		static = lines()
		inset = m.signal({ 0, 0, 0, 1 })
		view:render(ui(inset))
		first = lines()
		inset({ 0, 0, 0, 3 })
		reactive.flush()
	]])
	eq(child.lua_get("first ~= static"), true)
	eq(lines(), child.lua_get("static"))
end

T["shorthands"]["gap can follow a signal, rows and columns too"] = function()
	run([[
		gap = m.signal(0)
		view:render(m.grid({ columns = { 1, 1 }, gap = gap, m.block("a"), m.block("b"), m.block("c"), m.block("d") }))
		gap({ 1, 2 })
		reactive.flush()
	]])
	eq(lines(), { "a  b", "", "c  d" })
end

T["shorthands"]["a side given on its own wins over a dynamic shorthand"] = function()
	run([[
		padding = m.signal(1)
		view:render(m.block({ m.block({ "a", padding = padding, padding_left = 0, padding_top = 0 }) }))
		padding(2)
		reactive.flush()
	]])
	eq(lines(), { "a", "", "" })
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
	run(
		[[view:render(m.block({ width = 5, white_space = "nowrap", m.inline("the quick brown fox") }))]]
	)
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
	run(
		[[view:render(m.block({ m.block("one\ntwo"), m.block({ white_space = "nowrap", "three\nfour" }) }))]]
	)
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

-- Found by tests/test_fuzz.lua, seed 1003. A component wraps its content in
-- a group, which the change has to see past to reach the grid.
T["white_space"]["changing it inside a component lays the grid out again"] = function()
	run([[
		white_space = m.signal("normal")
		local Cell = m.component(function()
			return m.block({ white_space = white_space, "one two three four five six seven" })
		end)
		view:render(m.grid({ columns = 3, Cell() }))
		white_space("nowrap")
		reactive.flush()
	]])
	eq(lines(), { "one two three four five six seven" })
end

T["white_space"]["changing it back inside a component wraps again"] = function()
	run([[
		white_space = m.signal("nowrap")
		local Cell = m.component(function()
			return m.block({ white_space = white_space, "one two three four five six seven" })
		end)
		view:render(m.grid({ columns = 3, Cell() }))
		white_space("normal")
		reactive.flush()
	]])
	eq(lines(), { "one two three four", "five six seven" })
end

--- Six words of four letters, 29 cells: text that can wrap at every word.
local function words(letter)
	return ("%q"):format(vim.fn.join(vim.fn["repeat"]({ letter:rep(4) }, 6), " "))
end

T["overflow"] = new_set()

T["overflow"]["hidden cuts off what is too wide, too"] = function()
	run([[view:render(m.block({
		width = 4, overflow = "hidden", m.block({ white_space = "nowrap", "abcdefghij" }),
	}))]])
	eq(lines(), { "abcd" })
end

T["overflow"]["hidden cuts off what is too tall"] = function()
	run([[view:render(m.block({
		m.block({ height = 1, overflow = "hidden", m.block("a"), m.block("b") }),
		m.block("c"),
	}))]])
	eq(lines(), { "a", "c" })
end

T["overflow"]["overflow_y hidden cuts off what is too wide, as in CSS"] = function()
	run([[view:render(m.block({
		width = 4, overflow_y = "hidden", m.block({ white_space = "nowrap", "abcdefghij" }),
	}))]])
	eq(lines(), { "abcd" })
end

T["overflow"]["overflow_x hidden cuts off what is too tall, as in CSS"] = function()
	run([[view:render(m.block({
		m.block({ height = 1, overflow_x = "hidden", m.block("a"), m.block("b") }),
		m.block("c"),
	}))]])
	eq(lines(), { "a", "c" })
end

T["overflow"]["clip cuts off its own axis alone"] = function()
	run([[view:render(m.block({
		m.block({ width = 4, overflow_y = "clip", m.block({ white_space = "nowrap", "abcdefghij" }) }),
		-- Nothing after it, so the rows that run past it show as in a browser.
		m.block({ height = 1, overflow_x = "clip", m.block("a"), m.block("b") }),
	}))]])
	eq(lines(), { "abcdefghij", "a", "b" })
end

T["overflow"]["beside hidden, clip cuts off both axes"] = function()
	run([[view:render(m.block({
		m.block({
			width = 4, height = 1, overflow_x = "clip", overflow_y = "hidden",
			m.block({ white_space = "nowrap", "abcdefghij" }), m.block("b"),
		}),
		m.block("c"),
	}))]])
	eq(lines(), { "abcd", "c" })
end

T["overflow"]["the axis given on its own wins over the shorthand"] = function()
	run([[view:render(m.block({
		width = 4, overflow = "hidden", overflow_x = "visible",
		m.block({ white_space = "nowrap", "abcdefghij" }),
	}))]])
	-- `overflow_y` stays hidden, so `visible` along the row computes to cut off.
	eq(lines(), { "abcd" })
end

T["max_width"] = new_set()

T["max_width"]["text wraps inside it"] = function()
	run([[view:render(m.block({ max_width = 10, "aaaa bbbb cccc" }))]])
	eq(lines(), { "aaaa bbbb", "cccc" })
end

T["max_width"]["a narrower window still wins"] = function()
	run([[view:render(m.block({ max_width = 100, ("a"):rep(70) }))]])
	eq(lines(), { ("a"):rep(60), ("a"):rep(10) })
end

--- Every box under the root, in tree order, as `{ x, y, width, height }` of
--- the border box: what a browser would report for the same HTML and CSS.
local function boxes()
	return child.lua_get([[(function()
		local result, engine = {}, view.engine
		local function visit(id)
			for _, node in ipairs(engine:children(id, 0, 1000, true)) do
				if node.display ~= "text" then
					local top, right, bottom, left = unpack(node.margin)
					result[#result + 1] = {
						node.x + left,
						node.y + top,
						node.outer_width - left - right,
						node.outer_height - top - bottom,
					}
					if node.children > 0 then
						visit(node.id)
					end
				end
			end
		end
		visit(require("markup.view.protocol").ROOT)
		return result
	end)()]])
end

-- Layout as CSS lays it out. Each case renders the same as its HTML and CSS
-- in Chromium, which `make test BROWSER=1` checks.
T["css"] = new_set()

T["css"]["a box keeps its width, and what is wider runs past it"] = function()
	run([[view:render(m.block({ width = 5, white_space = "nowrap", "the quick brown" }))]])
	eq(boxes(), { { 0, 0, 5, 1 } })
	eq(lines(), { "the quick brown" })
end

T["css"]["a box keeps its height, and what is taller shows below it"] = function()
	run([[view:render(m.block({ m.block({ height = 1, m.block("a"), m.block("b") }) }))]])
	eq(boxes(), { { 0, 0, 60, 1 }, { 0, 0, 60, 1 }, { 0, 0, 60, 1 }, { 0, 1, 60, 1 } })
	eq(lines(), { "a", "b" })
end

T["css"]["margins of siblings collapse into the larger"] = function()
	run([[view:render(m.block({
		m.block({ "a", margin_bottom = 2 }),
		m.block({ "b", margin_top = 1 }),
	}))]])
	eq(boxes(), { { 0, 0, 60, 4 }, { 0, 0, 60, 1 }, { 0, 3, 60, 1 } })
end

T["css"]["a first child's margin passes through its parent"] = function()
	run([[view:render(m.block({ m.block({ m.block({ "a", margin_top = 2 }) }), m.block("b") }))]])
	-- The parent moves down with it, rather than growing.
	eq(boxes(), { { 0, 2, 60, 2 }, { 0, 2, 60, 1 }, { 0, 2, 60, 1 }, { 0, 3, 60, 1 } })
end

T["css"]["padding keeps a child's margin inside"] = function()
	run(
		[[view:render(m.block({ m.block({ padding_top = 1, m.block({ "a", margin_top = 2 }) }) }))]]
	)
	eq(boxes(), { { 0, 0, 60, 4 }, { 0, 0, 60, 4 }, { 0, 3, 60, 1 } })
end

T["css"]["an empty block lets its margins meet"] = function()
	run([[view:render(m.block({
		m.block("a"),
		m.block({ margin_top = 1, margin_bottom = 2 }),
		m.block("b"),
	}))]])
	-- It sits past its own top margin; its bottom one meets the next.
	eq(boxes(), { { 0, 0, 60, 4 }, { 0, 0, 60, 1 }, { 0, 2, 60, 0 }, { 0, 3, 60, 1 } })
end

T["css"]["an empty flex keeps its margins apart"] = function()
	run([[view:render(m.block({ m.flex({ margin_top = 1, margin_bottom = 1 }), "x" }))]])
	-- Its top margin passes through the block, its bottom one stays inside.
	eq(boxes(), { { 0, 1, 60, 2 }, { 0, 1, 60, 0 } })
	eq(lines(), { "", "", "x" })
end

T["css"]["a fraction track is no narrower than its content"] = function()
	run([[view:render(m.grid({
		columns = 3,
		m.block({ white_space = "nowrap", "one two three four five" }),
		m.block("b"),
		m.block("c"),
	}))]])
	-- 23 cells for the first track, and the other two share what is left.
	-- The other two share 37 cells: the edge between them, at 41.5 in a
	-- browser, goes back to 41.
	eq(boxes(), { { 0, 0, 60, 1 }, { 0, 0, 23, 1 }, { 23, 0, 18, 1 }, { 41, 0, 19, 1 } })
	eq(lines(), { "one two three four fiveb                 c" })
end

T["css"]["an inline with a width wraps inside it, as an inline-block"] = function()
	run([[view:render(m.block({ "x", m.inline({ width = 5, "aaa bbb" }) }))]])
	-- As CSS aligns it: "x" sits on the line of its last row.
	eq(lines(), { " aaa", "xbbb" })
end

T["css"]["an empty inline with a margin holds a line open"] = function()
	run([[view:render(m.block({ m.inline({ margin_left = 2 }), m.block("b") }))]])
	eq(boxes(), { { 0, 0, 60, 2 }, { 2, 0, 0, 1 }, { 0, 1, 60, 1 } })
end

T["css"]["neighbouring text in a flex is one item"] = function()
	run([[view:render(m.flex({ width = 10, justify = "between", "ab", "cd", m.block("x") }))]])
	-- One item "abcd", then "x": not three items spread apart.
	eq(lines(), { "abcd     x" })
end

T["css"]["text in a flex that is only white space is not drawn"] = function()
	run([[view:render(m.flex({ m.inline("a"), "   ", m.inline("b") }))]])
	eq(lines(), { "ab" })
end

T["css"]["a block in an inline breaks it in two around itself"] = function()
	run([[view:render(m.block({
		"x",
		m.inline({ padding_left = 1, padding_right = 1, "a", m.block("BLOCK"), "b" }),
		"y",
	}))]])
	-- The inline's left padding opens its first part, its right one closes
	-- its last; the block takes a row of its own, from the left edge.
	eq(lines(), { "x a", "BLOCK", "b y" })
end

T["css"]["an inline in a grid is a block"] = function()
	run([[view:render(m.grid({ columns = 1, m.inline({ "a", m.block("b") }) }))]])
	eq(lines(), { "a", "b" })
end

T["css"]["an auto track grows only with room left after the others"] = function()
	run([[view:render(m.block({ width = 20, m.grid({
		columns = { "auto", "1fr" },
		m.block("one two three four"),
		"averyverylongword",
	}) }))]])
	-- The word needs 17 cells and "three" 5: no room is left, so the auto
	-- track stays at its narrowest, and the two run past the 20.
	eq(lines(), { "one  averyverylongword", "two", "three", "four" })
end

T["css"]["a grid that fits its content takes what its tracks need"] = function()
	run(
		[[view:render(m.block({ m.inline({ width = "fit", m.grid({ columns = { "auto", "1fr" }, "ab", m.block("cd") }) }), "|" }))]]
	)
	eq(lines(), { "abcd|" })
end

T["css"]["a closing collapse in a grid is as short as a fresh one"] = function()
	-- Found by tests/test_fuzz.lua once it compared boxes: closing kept the
	-- collapse's height "auto", so the grid stretched it to its row.
	run([[
		Markup.animate.enabled = false
		open = m.signal(true)
		view:render(m.block({ m.grid({ columns = 2, m.collapse(open, function() return m.block({}) end), "x" }) }))
		open(false)
		reactive.flush()
	]])
	eq(boxes(), { { 0, 0, 60, 1 }, { 0, 0, 60, 1 }, { 0, 0, 30, 0 } })
end

T["css"]["no longer wrapping paints a box where it is"] = function()
	-- Found by tests/test_fuzz.lua: a block kept the pieces of an earlier wrap.
	run([=[
		white_space = m.signal("normal")
		view:render(m.flex({ m.inline({ white_space = white_space, m.block({ padding = 1, style = "Search" }) }) }))
		white_space("nowrap")
		reactive.flush()
		ids = vim.api.nvim_buf_get_extmarks(win.buf, view.ns, 0, -1, { details = true })
		rows = {}
		for _, mark in ipairs(ids) do
			if mark[4].hl_group == "Search" then rows[#rows + 1] = mark[2] end
		end
		table.sort(rows)
	]=])
	-- The whole box, both rows, as a fresh render paints it.
	eq(child.lua_get("rows"), { 0, 1 })
end

T["css"]["a block fills a box sized to its content"] = function()
	-- Found by comparing tests/test_fuzz.lua with Chromium, seed 1004: an empty
	-- block in a `fit` box took no width.
	run([[view:render(m.block({ width = "fit", m.block({ height = 1 }), "xyz" }))]])
	eq(boxes(), { { 0, 0, 3, 2 }, { 0, 0, 3, 1 } })
end

T["css"]["a line breaks before an inline-block that does not fit"] = function()
	-- Found by comparing tests/test_fuzz.lua with Chromium, seed 17: it stayed
	-- on the line, past its end.
	run([[view:render(m.block({ width = 3, "abc", m.inline({ width = 1, height = 2 }) }))]])
	eq(boxes(), { { 0, 0, 3, 3 }, { 0, 1, 1, 2 } })
end

-- Found by comparing tests/test_fuzz.lua with Chromium, seeds 20, 1007 and
-- 2010: each broke words narrower than the longest, which CSS `fit-content`
-- and `min-width: auto` keep whole.
T["css"]["a box sized to its content is no narrower than its longest word"] = function()
	run([[view:render(m.block({ width = 3, m.block({ width = "fit", "ipsum dolor" }) }))]])
	eq(boxes(), { { 0, 0, 3, 2 }, { 0, 0, 5, 2 } })
	eq(lines(), { "ipsum", "dolor" })
end

T["css"]["text in a column keeps its longest word"] = function()
	run([[view:render(m.flex({ vertical = true, align = "start", width = 3, "ipsum dolor" }))]])
	eq(boxes(), { { 0, 0, 3, 2 } })
	eq(lines(), { "ipsum", "dolor" })
end

T["css"]["a grid row is as tall as its item laid out at its own width"] = function()
	run(
		[[view:render(m.grid({ columns = { 5, "1fr" }, m.block({ width = "fit", "xipsum dolor" }) }))]]
	)
	eq(boxes(), { { 0, 0, 60, 2 }, { 0, 0, 6, 2 } })
end

T["css"]["a flex item with a share does not shrink below its longest word"] = function()
	run(
		[[view:render(m.block({ width = 10, m.flex({ "abcdefgh", m.block({ width = "full", "abcdefgh" }) }) }))]]
	)
	eq(lines(), { "abcdefghabcdefgh" })
end

T["css"]["fraction tracks share a fraction size in a fit grid"] = function()
	run([[view:render(m.grid({ width = "fit", columns = 3, "xx" }))]])
	eq(boxes(), { { 0, 0, 6, 1 } })
end

T["css"]["an absolute auto width fits between its inset and the far edge"] = function()
	run(
		[[view:render(m.block({ position = "absolute", left = 9, m.grid({ columns = 2, string.rep("x", 30) }) }))]]
	)
	eq(boxes(), { { 9, 0, 51, 1 }, { 9, 0, 51, 1 } })
end

T["css"]["a percentage child fills the resolved fit width"] = function()
	run([[view:render(m.block({ width = "fit", m.block({ width = "full" }), "abc" }))]])
	eq(boxes(), { { 0, 0, 3, 1 }, { 0, 0, 3, 0 } })
end

T["css"]["an empty flex item can shrink below its specified width"] = function()
	run([[view:render(m.flex({ width = 5, m.block({ width = 3 }), "abcde" }))]])
	eq(boxes(), { { 0, 0, 5, 1 }, { 0, 0, 0, 1 } })
end

T["css"]["a wrapped column fits centered items to their flex line"] = function()
	run([[view:render(m.flex({ width = 3, vertical = true, wrap = true, align = "center",
		m.block("aa bb"), "abcdefghij" }))]])
	eq(boxes(), { { 0, 0, 3, 3 }, { 2, 0, 5, 2 } })
end

T["css"]["anonymous flex text wraps before fractional edges snap to cells"] = function()
	run([[view:render(m.flex({ width = 7, m.block({ width = 6 }), "日本語" }))]])
	eq(lines(), { "   日", "   本", "   語" })
end

T["css"]["an inline-block inherits its last overflowing line baseline"] = function()
	run(
		[[view:render(m.block({ m.inline({ width = 3, m.block({ height = 1, "ipsum dolor" }) }) }))]]
	)
	eq(boxes()[1], { 0, 0, 60, 4 })
end

T["css"]["spacing separates an empty block from the following inline run"] = function()
	run(
		[[view:render(m.block({ spacing = 1, m.block({}), "a", m.inline({ m.block("b"), "c" }) }))]]
	)
	eq(lines(), { "", "a", "b", "c" })
end

T["css"]["a full-width blank inline-block has only its own blank line"] = function()
	run([[view:render(m.block({ m.inline({ border = "rounded", width = "full", "" }) }))]])
	eq(boxes()[1], { 0, 0, 60, 3 })
end

T["css"]["a split inline's leading padding can wrap after a full word"] = function()
	run(
		[[view:render(m.block({ width = 3, "abc", m.inline({ padding_left = 1, m.block("x") }) }))]]
	)
	eq(boxes()[1], { 0, 0, 3, 3 })
	eq(boxes()[3], { 0, 2, 3, 1 })
end

T["css"]["a clipped descendant caps the baseline of an inline-block"] = function()
	run(
		[[view:render(m.block({ m.inline({ width = 3, m.block({ height = 1, overflow = "hidden", "ipsum dolor" }) }) }))]]
	)
	eq(boxes()[1], { 0, 0, 60, 1 })
end

T["css"]["a flex descendant supplies the baseline of an inline-block"] = function()
	run([[view:render(m.block({ m.inline({ height = 1, m.block("x"), m.flex({ "y" }) }) }))]])
	eq(boxes()[1], { 0, 0, 60, 2 })
end

T["css"]["a percentage inline-block fits its content during grid sizing"] = function()
	run(
		[[view:render(m.grid({ width = 3, columns = 1, m.block({ m.inline({ width = "full", "tab\there" }) }) }))]]
	)
	eq(boxes(), { { 0, 0, 3, 2 }, { 0, 0, 4, 2 }, { 0, 0, 4, 2 } })
end

T["flex"] = new_set()

T["flex"]["lays items out in a row"] = function()
	run([[view:render(m.flex({ gap = 1, m.block("a"), m.block("bb"), m.block("c") }))]])
	eq(lines(), { "a bb c" })
end

-- Found by tests/test_fuzz.lua, seeds 123 and 166: both set the direction,
-- and whichever `pairs` met last won.
T["flex"]["direction wins over vertical"] = function()
	run([[view:render(m.flex({ vertical = true, direction = "row", m.block("a"), m.block("b") }))]])
	eq(lines(), { "ab" })
end

T["flex"]["direction wins over vertical when it changes"] = function()
	run([[
		direction = m.signal("column")
		view:render(m.flex({ vertical = true, direction = direction, m.block("a"), m.block("b") }))
		direction("row")
		reactive.flush()
		first = lines()
		view:render(m.flex({ vertical = true, direction = direction, m.block("a"), m.block("b") }))
		reactive.flush()
	]])
	eq(child.lua_get("first"), { "ab" })
	eq(lines(), { "ab" })
end

T["flex"]["vertical can follow a signal"] = function()
	run([[
		vertical = m.signal(false)
		view:render(m.flex({ vertical = vertical, m.block("a"), m.block("b") }))
		first = lines()
		vertical(true)
		reactive.flush()
	]])
	eq(child.lua_get("first"), { "ab" })
	eq(lines(), { "a", "b" })
end

T["flex"]["pushes items apart"] = function()
	run(
		[[view:render(m.flex({ width = 20, justify = "between", m.block("left"), m.block("right") }))]]
	)
	eq(lines(), { "left           right" })
end

T["flex"]["grows an item into free space"] = function()
	run([[view:render(m.flex({ width = 20, m.block({ "a", grow = 1 }), m.block("end") }))]])
	eq(lines(), { "a                end" })
end

T["flex"]["stacks with vflex and vertical"] = function()
	run(
		[[view:render(m.block({ m.vflex({ m.block("a"), m.block("b") }), m.flex({ vertical = true, m.block("c") }) }))]]
	)
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

-- The cases below render the same, cell for cell, as their HTML and CSS do in
-- a browser, with `overflow-wrap: break-word` and `box-sizing: content-box`.
T["flex"]["a shrunk inline item wraps its text inside itself"] = function()
	run([[view:render(m.flex({ width = 14, m.inline("aaaa bbbb cccc"), m.block("ddddd ddddd") }))]])
	-- The inline gets 8 cells and its text breaks inside them, rather than
	-- running on under the block next to it.
	eq(lines(), { "aaaa    ddddd", "bbbb    ddddd", "cccc" })
end

T["flex"]["a margin does not shrink and does not weigh in"] = function()
	run([[view:render(m.flex({
		width = 30, m.block({ "aaaa aaaaa", margin_left = 20 }), m.block("bbbb bbbbb"),
	}))]])
	eq(lines(), { "                    aaaa bbbb", "                    aaaaabbbbb" })
end

T["flex"]["an item that cannot wrap does not shrink below its text"] = function()
	run([[view:render(m.flex({
		width = 14, m.block({ "aaaaaaaaaa", white_space = "nowrap" }), m.block("bb bb bb b"),
	}))]])
	eq(lines(), { "aaaaaaaaaabb", "          bb", "          bb b" })
end

T["flex"]["an item does not shrink below its longest word"] = function()
	run([[view:render(m.flex({ width = 12, m.block("aaaaaaaa a"), m.block("bb bb bb b") }))]])
	eq(lines(), { "aaaaaaaabb", "a       bb", "        bb b" })
end

T["flex"]["an item that clips may shrink below its text"] = function()
	run([[view:render(m.flex({
		width = 14,
		m.block({ "aaaaaaaaaa", white_space = "nowrap", overflow = "hidden" }),
		m.block("bbbb bbbbb"),
	}))]])
	eq(lines(), { "aaaaaaabbbb", "       bbbbb" })
end

T["flex"]["max_width narrows what the items get"] = function()
	run(
		([[view:render(m.flex({ max_width = 40, m.block(%s), m.block(%s) }))]]):format(
			words("a"),
			words("b")
		)
	)
	eq(lines(), {
		"aaaa aaaa aaaa aaaa bbbb bbbb bbbb bbbb",
		"aaaa aaaa           bbbb bbbb",
	})
end

T["flex"]["min_width widens what the items get"] = function()
	run([[view:render(m.block({
		width = 6,
		m.flex({ min_width = 10, justify = "between", m.block("a"), m.block("b") }),
	}))]])
	eq(lines(), { "a        b" })
end

--- What the window shows, text and highlights alike, compared with the
--- screenshot saved under tests/screenshots. Nothing around the buffer, such
--- as a status line, differs between Neovim versions.
local function expect_screen(code)
	child.lua([[
		vim.o.laststatus, vim.o.ruler, vim.o.showmode = 0, false, false
		vim.opt.fillchars = { eob = " " }
		-- A group of its own for each part, so each shows apart in the screenshot.
		vim.api.nvim_set_hl(0, "Box", { bg = "#f5a97f" })
		vim.api.nvim_set_hl(0, "Item", { bg = "#a6da95" })
		vim.api.nvim_set_hl(0, "Other", { bg = "#8aadf4" })
		vim.api.nvim_set_hl(0, "Third", { bg = "#c6a0f6" })
	]])
	child.o.lines, child.o.columns = 16, 30
	run(code)
	run("vim.cmd('redraw')")
	MiniTest.expect.reference_screenshot(child.get_screenshot())
end

T["flex"]["what stretches stops at max_height"] = function()
	-- `a` stretches to the line, which is no taller than the flex, though
	-- the item beside it is: its highlight does not reach past the flex.
	expect_screen([[view:render(m.block({
		m.flex({
			max_height = 3, max_width = 10, style = "Box", overflow_x = "hidden",
			m.inline({ "a", style = "Item" }),
			m.inline({ "b\nb\nb\nb\nb", padding_left = 20 }),
			m.block({ "c", style = "Other" }),
		}),
		m.block("after"),
	}))]])
end

T["flex"]["overflow_x hidden cuts off what is too tall and its highlights"] = function()
	-- As in CSS: `hidden` along the row makes `visible` along the column cut
	-- off as well, so the rows of `b` past max_height do not show.
	expect_screen([[view:render(m.block({
		m.flex({
			max_height = 2, width = 8, style = "Box", overflow_x = "hidden",
			m.block({ "a", style = "Item" }),
			m.block({ "b\nb\nb\nb", style = "Other" }),
		}),
		m.block("after"),
	}))]])
end

T["flex"]["overflow hidden cuts off highlights too"] = function()
	-- The third row of `b` and the end of `c` are past the flex, and neither
	-- their text nor their highlights show there.
	expect_screen([[view:render(m.block({
		m.flex({
			width = 6, max_height = 2, style = "Box", overflow = "hidden",
			m.block({ "aa", style = "Item" }),
			m.block({ "b\nb\nb", style = "Other" }),
			m.block({ "cccccccccc", white_space = "nowrap", style = "Third" }),
		}),
		m.block("after"),
	}))]])
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
	run(
		[[view:render(m.grid({ width = 9, columns = 3, m.block("a"), m.block("b"), m.block("c") }))]]
	)
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

T["grid"]["is as wide as the view when full, inside an inline"] = function()
	-- A tall element among inline ones once laid out at a width of i32::MAX.
	run(
		[[view:render(m.inline({ m.grid({ columns = 2, width = "full", m.inline("a"), "b", "c" }) }))]]
	)
	-- As CSS: neighbouring text is one item, so "b" and "c" share a cell.
	eq(lines(), { "a" .. (" "):rep(29) .. "bc" })
end

T["grid"]["survives clipping a full width grid inside an inline"] = function()
	-- Found by tests/test_fuzz.lua: this asked for a 1 GiB line and died.
	run([[
		clip = m.signal("visible")
		view:render(m.inline({ m.grid({ columns = 2, width = "full", overflow_x = clip, m.inline("a"), "b", "c" }) }))
		clip("hidden")
		reactive.flush()
	]])
	-- As CSS: neighbouring text is one item, so "b" and "c" share a cell.
	eq(lines(), { "a" .. (" "):rep(29) .. "bc" })
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
				return m.block("row " .. item())
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

T["each"]["updates item and index without remounting retained keys"] = function()
	run([[
		local a, b = { id = 1, name = "a" }, { id = 2, name = "b" }
		items = m.signal({ a, b })
		mounts = 0
		view:render(m.each(items, function(item, index)
			mounts = mounts + 1
			local original = item().name
			return m.block(function() return index() .. original .. item().name end)
		end, { key = function(item) return item.id end }))
		items({ { id = 2, name = "B" }, { id = 1, name = "A" } })
		reactive.flush()
	]])
	eq(lines(), { "1bB", "2aA" })
	eq(child.lua_get("mounts"), 2)
end

T["each"]["replacing a function-valued item preserves its value"] = function()
	run([[
		local a, b = function() return "old" end, function() return "new" end
		local items = m.signal({ a })
		view:render(m.each(items, function(item)
			return m.block(function() return item()() end)
		end, { key = function() return 1 end }))
		items({ b })
		reactive.flush()
	]])
	eq(lines(), { "new" })
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

T["press"]["<CR> presses like a click"] = function()
	run([[
		pressed = 0
		view:render(m.block({
			m.block("nothing"),
			m.button({ "press me", on_press = function() pressed = pressed + 1 end }),
		}))
		vim.api.nvim_win_set_cursor(0, { 2, 2 })
	]])
	child.type_keys("<CR>")
	eq(child.lua_get("pressed"), 1)
end

T["press"]["<CR> over nothing to press moves down, as it always did"] = function()
	run([[
		pressed = false
		view:render(m.block({
			m.block("nothing"),
			m.block("more"),
			m.button({ "press me", on_press = function() pressed = true end }),
		}))
		vim.api.nvim_win_set_cursor(0, { 1, 0 })
	]])
	child.type_keys("<CR>")
	eq(child.lua_get("vim.api.nvim_win_get_cursor(0)[1]"), 2)
	eq(child.lua_get("pressed"), false)
end

T["press"]["press_key binds other keys instead"] = function()
	run([[
		pressed = 0
		vim.cmd("only | new")
		win = Markup.window({ position = "current", hijack = true, show = false, minimal = false })
		win.buf = vim.api.nvim_get_current_buf()
		win:show()
		view = Markup.view(win, { press_key = { "<Space>", "x" } })
		view:render(m.block({
			m.button({ "press me", on_press = function() pressed = pressed + 1 end }),
			m.block("below"),
		}))
		vim.api.nvim_win_set_cursor(0, { 1, 0 })
	]])
	child.type_keys("<Space>", "x")
	eq(child.lua_get("pressed"), 2)
	eq(child.lua_get([[vim.fn.maparg("<CR>", "n")]]), "")
end

T["press"]["press_key = false binds nothing"] = function()
	run([[
		vim.cmd("only | new")
		win = Markup.window({ position = "current", hijack = true, show = false, minimal = false })
		win.buf = vim.api.nvim_get_current_buf()
		win:show()
		view = Markup.view(win, { press_key = false })
		view:render(m.button({ "press me", on_press = function() end }))
	]])
	eq(child.lua_get([[vim.fn.maparg("<CR>", "n")]]), "")
end

T["press"]["a component can take <CR> over, and give it back"] = function()
	run([[
		pressed, taken = 0, 0
		open = m.signal(true)
		local Taker = m.component(function()
			m.use_key("<CR>", function() taken = taken + 1 end)
			return m.block("taker")
		end)
		view:render(m.block({
			m.button({ "press me", on_press = function() pressed = pressed + 1 end }),
			m.show(open, function() return Taker() end),
		}))
		vim.api.nvim_win_set_cursor(0, { 1, 0 })
	]])
	child.type_keys("<CR>")
	eq(child.lua_get("{ pressed, taken }"), { 0, 1 })
	run("open(false); reactive.flush()")
	child.type_keys("<CR>")
	eq(child.lua_get("{ pressed, taken }"), { 1, 1 })
	eq(
		child.lua_get(
			[[vim.fn.maparg("<CR>", "n") ~= "" or #vim.api.nvim_buf_get_keymap(win.buf, "n") > 0]]
		),
		true
	)
end

T["press"]["a destroyed view lets go of <CR>"] = function()
	run([[
		pressed = false
		view:render(m.button({ "press me", on_press = function() pressed = true end }))
		view:destroy()
	]])
	-- The window outlives the view, and the key must not keep the view alive.
	eq(child.lua_get([[vim.fn.maparg("<CR>", "n")]]), "")
	eq(child.lua_get("view.key_stacks['n <CR>'] == nil"), true)
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
							return m.block({ m.inline("item " .. item(), "Comment") })
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

T["updates of flex cards in a grid match a fresh render"] = function()
	run([[
		-- Flex and grid size what they hold several ways before placing it, and
		-- keep those sizes while nothing changes: what changes must be placed anew.
		local seed = 4242
		local function rnd(n)
			seed = (seed * 16807) % 2147483647
			return seed % n + 1
		end
		local words = { "signal", "a longer label", "x", "effect memo", "" }

		local names, values, widths = {}, {}, {}
		for i = 1, 6 do
			names[i] = m.signal(words[i % #words + 1])
			values[i] = m.signal(("%d%%"):format(i * 10))
			widths[i] = m.signal(10 + i)
		end

		local function Cards()
			local cards = {}
			for i = 1, 6 do
				cards[i] = m.block({
					border = "rounded",
					padding = { 0, 1 },
					m.flex({
						justify = "between",
						m.block({ m.inline("card "), m.inline(names[i], "String") }),
						m.inline(values[i], "Number"),
					}),
					m.flex({
						gap = 1,
						m.inline(names[i], "Comment"),
						m.block({
							width = function() return widths[i]() end,
							-- Shrinking by a fraction of a cell would wrap the text where
							-- no terminal can: what this checks is the sizes kept.
							shrink = 0,
							white_space = "normal",
							"wraps at the width it is given",
						}),
					}),
				})
			end
			return m.grid({ columns = 3, gap = { 0, 1 }, cards })
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
			target:render(Cards())
			local result = snapshot(target)
			target:unmount()
			reactive.flush()
			other:close()
			return result
		end

		view:render(Cards())
		failures, steps = {}, 0
		for step = 1, 150 do
			local i = rnd(6)
			local action = rnd(3)
			if action == 1 then
				names[i](words[rnd(#words)])
			elseif action == 2 then
				values[i](("%d%%"):format(rnd(100)))
			else
				widths[i](rnd(20))
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
	eq(child.lua_get("steps"), 150)
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
	eq(
		child.lua_get("vim.api.nvim_buf_get_lines(hidden.buf, 0, -1, false)")[1]:gsub("%s+$", ""),
		"second"
	)
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
	eq(
		child.lua_get("vim.api.nvim_buf_get_lines(hidden.buf, 0, -1, false)")[1]:gsub("%s+$", ""),
		"content"
	)
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
			return m.block({ name, width = "fit", click = click, on_press = function() pressed = name end })
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

T["snap"]["passes over what is inert"] = function()
	run([[
		view = Markup.view(win, { snap = true })
		away = m.signal(true)
		local function item(name)
			return m.block({ name, width = "fit", on_press = function() end })
		end
		view:render(m.block({
			item("one"),
			m.block({ inert = away, m.block(""), item("two") }),
			m.block(""),
			item("three"),
		}))
		vim.api.nvim_win_set_cursor(0, { 1, 0 })
		view.cursor = { 1, 0 }
	]])
	child.type_keys("j")
	eq(child.lua_get("vim.api.nvim_win_get_cursor(0)")[1], 5)

	-- Back in reach once it is not.
	run("away(false)")
	child.type_keys("k")
	eq(child.lua_get("vim.api.nvim_win_get_cursor(0)")[1], 3)
end

T["snap"]["what is inert is neither hovered nor pressed"] = function()
	run([[
		view = Markup.view(win)
		hovered, pressed = false, false
		view:render(m.block({
			inert = true,
			m.block({
				"button",
				on_press = function() pressed = true end,
				on_hover = function(on) hovered = on end,
			}),
		}))
		vim.api.nvim_win_set_cursor(0, { 1, 0 })
		vim.api.nvim_exec_autocmds("CursorMoved", { buffer = view.win.buf })
		view:press()
	]])
	eq(child.lua_get("hovered"), false)
	eq(child.lua_get("pressed"), false)
end

T["hold_cursor"] = new_set()

local function moving_view()
	run([[
		view = Markup.view(win, { snap = true })
		above = m.signal(0)
		hovered = {}
		local function item(name)
			return m.block({
				name,
				width = "fit",
				on_press = function() end,
				on_hover = function(on) if on then hovered[#hovered + 1] = name end end,
			})
		end
		view:render(m.block({
			m.block("title"),
			function()
				local rows = {}
				for i = 1, above() do rows[i] = m.block("") end
				return m.block(rows)
			end,
			item("one"),
			m.block(""),
			item("two"),
		}))
		reactive.flush()
		vim.api.nvim_win_set_cursor(0, { 2, 0 })
		view.cursor = nil
		vim.api.nvim_exec_autocmds("CursorMoved", { buffer = view.win.buf })
		hovered = {}
	]])
end

T["hold_cursor"]["keeps the cursor still while rows come in above it"] = function()
	moving_view()
	run([[
		release = view:hold_cursor({ 1, 0 })
		above(5)
		reactive.flush()
		vim.api.nvim_exec_autocmds("CursorMoved", { buffer = view.win.buf })
	]])
	eq(child.lua_get("vim.api.nvim_win_get_cursor(0)")[1], 1)
	-- Nothing passing under it is hovered.
	eq(child.lua_get("hovered"), {})
	eq(child.lua_get("view.hovered"), vim.NIL)
end

T["hold_cursor"]["lets go onto the nearest node"] = function()
	moving_view()
	run([[
		release = view:hold_cursor({ 1, 0 })
		above(3)
		reactive.flush()
		release()
	]])
	-- "one" moved down by three rows, and the cursor snapped onto it.
	eq(child.lua_get("vim.api.nvim_win_get_cursor(0)")[1], 5)
	eq(child.lua_get("hovered"), { "one" })
end

T["hold_cursor"]["a release of an older hold does nothing"] = function()
	moving_view()
	run([[
		first = view:hold_cursor({ 1, 0 })
		second = view:hold_cursor({ 1, 0 })
		first()
	]])
	eq(child.lua_get("view.held ~= nil"), true)
	run("second()")
	eq(child.lua_get("view.held"), vim.NIL)
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
	eq(
		child.lua_get(
			"vim.api.nvim_get_option_value('scrolloff', { scope = 'local', win = win.win })"
		),
		0
	)

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

--- Starts a text snapping view of `ui`, with the cursor on its first row.
local function text_snapping(ui)
	child.lua(([[
		view = Markup.view(win, { snap = "text" })
		view:render(%s)
		reactive.flush()
		vim.api.nvim_win_set_cursor(win.win, { 1, 0 })
		view.cursor = nil
		view:snap_cursor()
	]]):format(ui))
end

local function current_line()
	return child.lua_get("vim.trim(vim.api.nvim_get_current_line())")
end

T["snap"]["text mode passes over text that does not snap"] = function()
	text_snapping([[m.block({
		m.block("one"),
		m.block({ snap = false, m.block("skipped"), m.block("this too") }),
		m.block("two"),
	})]])
	eq(current_line(), "one")
	child.type_keys("j")
	eq(current_line(), "two")
	child.type_keys("k")
	eq(current_line(), "one")
end

T["snap"]["text mode lands on a button where text does not snap"] = function()
	text_snapping([[m.block({
		m.block("one"),
		m.block({ snap = false, m.block("label"), m.block({ on_press = function() end, "button" }) }),
	})]])
	child.type_keys("j")
	eq(current_line(), "button")
end

T["snap"]["text can snap again inside text that does not"] = function()
	text_snapping([[m.block({
		m.block("one"),
		m.block({ snap = false, m.block("skipped"), m.block({ snap = true, "back" }) }),
	})]])
	child.type_keys("j")
	eq(current_line(), "back")
end

T["snap"]["whether text snaps can follow a signal"] = function()
	child.lua([[skip = m.signal(false)]])
	text_snapping([[m.block({
		m.block("one"),
		m.block({ snap = function() return not skip() end, "middle" }),
		m.block("two"),
	})]])
	child.type_keys("j")
	eq(current_line(), "middle")
	child.lua([[skip(true); reactive.flush()]])
	child.type_keys("k", "j")
	eq(current_line(), "two")
end

T["snap"]["absolute text inside text that does not snap does not snap either"] = function()
	text_snapping([[m.block({
		m.block("one"),
		m.block({
			snap = false,
			position = "relative",
			m.block("     "),
			m.block({ position = "absolute", top = 0, left = 0, "floating" }),
		}),
		m.block("two"),
	})]])
	child.type_keys("j")
	eq(current_line(), "two")
end

T["snap"]["gg and G stop at the first and last text that snaps"] = function()
	text_snapping([[m.block({
		m.block({ snap = false, "header" }),
		m.block("one"),
		m.block("two"),
		m.block({ snap = false, "footer" }),
	})]])
	eq(current_line(), "one")
	child.type_keys("G")
	eq(current_line(), "two")
	child.type_keys("gg")
	eq(current_line(), "one")
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
		view = Markup.view(win)
		click = %s
		local function button(name)
			return m.block({ name, width = "fit", click = click, on_press = function() pressed = name end })
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

T["click"]["the margin is not part of what is pressed"] = function()
	child.lua([[
		pressed = nil
		view:render(m.block({
			m.block("title"),
			m.block({
				"go",
				width = "fit",
				margin = { 1, 0, 0, 4 },
				padding = { 0, 1 },
				on_press = function() pressed = true end,
			}),
		}))
		reactive.flush()
	]])
	-- The row above it and the cells to its left are margin.
	click(1, 5, 1)
	click(2, 2, 1)
	eq(child.lua_get("pressed"), vim.NIL)
	-- Its padding is part of it.
	click(2, 4, 1)
	eq(child.lua_get("pressed"), true)
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
	-- The selection ends at the latest once Neovim has handled what was typed
	-- (SafeState), which a vim.wait inside one call never reaches. Asked from
	-- here, Neovim gets there between the questions.
	eq(
		vim.wait(2000, function()
			return child.fn.mode() == "n"
		end, 10),
		true
	)
end

-- As a hand clicks: the button comes up a while after it went down. Neovim
-- selects the word again on that last release, <2-LeftRelease>.
T["click"]["with double, the word stays unselected when the button comes up late"] = function()
	click_view("double")
	local screen = child.lua_get("vim.fn.screenpos(win.win, 4, 2)")
	local function mouse(action)
		child.api.nvim_input_mouse("left", action, "", 0, screen.row - 1, screen.col - 1)
	end
	mouse("press")
	mouse("release")
	mouse("press")
	-- Long enough for Neovim to handle the press and wait for the release.
	vim.wait(100, function()
		return false
	end, 10)
	child.fn.mode()
	mouse("release")
	eq(
		vim.wait(2000, function()
			return child.lua_get("pressed") == "two" and child.fn.mode() == "n"
		end, 10),
		true
	)
	-- And it stays that way.
	vim.wait(100, function()
		return false
	end, 10)
	eq(child.fn.mode(), "n")
end

T["click"]["each button says which click it takes"] = function()
	child.lua([[
		pressed = nil
		view = Markup.view(win)
		view:render(m.block({
			m.block({ "single", width = "fit", on_press = function() pressed = "single" end }),
			m.block({ "double", width = "fit", click = "double", on_press = function() pressed = "double" end }),
		}))
		reactive.flush()
	]])
	click(1, 1, 1)
	eq(child.lua_get("pressed"), vim.NIL)
	click(0, 1, 1)
	eq(child.lua_get("pressed"), "single")
	click(1, 1, 2)
	eq(child.lua_get("pressed"), "double")
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

T["wide text"]["a combining accent takes no cell of its own"] = function()
	-- "e" with U+0301 is one cell, as Neovim draws it: what follows is next
	-- to it, not a cell further on.
	run([[view:render(m.flex({ m.inline("e\u{301}te\u{301}"), m.inline("|") }))]])
	eq(lines(), { "e\u{301}te\u{301}|" })
end

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
	run(
		[[view:render(m.block({ m.block({ "ab", width = 2, border = "single", border_sides = { "top" } }) }))]]
	)
	eq(lines(), { "──", "ab" })
end

T["border"]["takes custom characters"] = function()
	run([[view:render(m.block({ m.block({ "a", width = 1, border = { chars = "+-+|+-+|" } }) }))]])
	eq(lines(), { "+-+", "|a|", "+-+" })
end

T["border"]["uses border_style"] = function()
	run(
		[[view:render(m.block({ m.block({ "a", width = 1, border = "single", border_style = "Label" }) }))]]
	)
	eq(marks()[1][4], "Label")
end

T["border"]["works in flex and wraps inside"] = function()
	run([[view:render(m.flex({
		width = 12, gap = 1,
		m.block({ "aaaa bbbb", border = "single", grow = 1 }),
		m.block({ "x", border = "single", shrink = 0 }),
	}))]])
	eq(lines(), {
		"┌──────┐ ┌─┐",
		"│aaaa  │ │x│",
		"│bbbb  │ │ │",
		"└──────┘ └─┘",
	})
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
	eq(
		child.lua_get(
			"vim.trim(vim.api.nvim_buf_get_lines(band.win.buf, 0, 1, false)[1]):sub(1, 3)"
		),
		"▄"
	)
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
	return child.lua_get(
		"vim.tbl_map(vim.trim, vim.api.nvim_buf_get_lines(band.win.buf, 0, -1, false))"
	)
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

	child.lua(
		"visible(true); reactive.flush(); reactive.flush(); visible(false); reactive.flush(); reactive.flush()"
	)
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

T["fixed"]["the height can be tracked"] = function()
	overlay_view()
	child.lua([[
		seen = {}
		reactive.effect(function() seen[#seen + 1] = view:rows() end)
		vim.cmd("new")
		vim.api.nvim_win_set_height(win.win, 10)
	]])
	child.lua("vim.wait(20, function() return false end, 5)")
	child.lua("reactive.flush()")
	eq(child.lua_get("seen[1] > 10"), true)
	eq(child.lua_get("seen[#seen]"), 10)
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

T["fixed"]["a borderless band tracks its highlight"] = function()
	run([[
		style = m.signal("Visual")
		view:render(m.block({ position = "fixed", style = style, "header" }))
		band = view.fixed[1]
	]])
	eq(child.lua_get("vim.wo[band.win.win].winhighlight"), "Normal:Visual")
	run([[style({bg = "#123456"}); reactive.flush()]])
	eq(
		child.lua_get([[vim.wo[band.win.win].winhighlight:match("^Normal:MarkupStyle%d+$") ~= nil]]),
		true
	)
	run([[style(nil); reactive.flush()]])
	eq(
		child.lua_get("vim.wo[band.win.win].winhighlight"),
		child.lua_get("vim.wo[win.win].winhighlight")
	)
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
	run([[vim.cmd("vsplit")]])
	-- The band follows WinResized, which Neovim sends from its main loop: a
	-- vim.wait inside one call never turns it. Asked from here, the loop turns
	-- between the questions.
	local same = "vim.api.nvim_win_get_width(band.win.win) == vim.api.nvim_win_get_width(win.win)"
	eq(
		vim.wait(2000, function()
			return child.lua_get(same)
		end, 10),
		true
	)
end

T["fixed"]["closes and reopens with its window"] = function()
	run([[
		host = Markup.window({ position = "right", enter = false, show = true, width = 0.4 })
		hosted = Markup.view(host)
		hosted:render(m.block({ m.block({ "pinned", position = "fixed" }), m.block("body") }))
		reactive.flush()
		band = hosted.fixed[1]
		host:hide()
		vim.wait(2000, function() return not band.win:win_valid() end, 5)
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

T["lifecycle"]["unmounting clears the buffer and the engine"] = function()
	run([[
		view:render(m.block({ m.block("one"), m.block("two") }))
		view:unmount()
		reactive.flush()
	]])
	eq(lines(), { "" })
	eq(child.lua_get("view.engine:node_count()"), 1)
end

-- One bad command used to drop every command after it in the frame, leaving
-- the engine apart from what the view thinks it holds. Effects run in an order
-- that changed from one session to the next, so what got lost did too.
T["lifecycle"]["text that is not UTF-8 shows, and the rest of its frame too"] = function()
	run([[
		reported = {}
		vim.notify = function(message) reported[#reported + 1] = message end
		a, b = m.signal("a"), m.signal("b")
		view:render(m.block({ m.inline(function() return a() end), m.inline(" "), m.inline(function() return b() end) }))
		a("x\255y")
		b("second")
		reactive.flush()
		vim.wait(10)
	]])
	eq(lines(), { "x\u{fffd}y second" })
	eq(child.lua_get("reported"), {})
end

T["lifecycle"]["a command for a node that is gone loses nothing else"] = function()
	run([[
		reported = {}
		vim.notify = function(message) reported[#reported + 1] = message end
		text = m.signal("before")
		view:render(m.block({ m.inline(function() return text() end) }))
		view.commands:set_style(99999, "width", 3)
		text("after")
		reactive.flush()
		vim.wait(10)
	]])
	eq(lines(), { "after" })
	-- Still said, once, so the bug behind it can be found.
	eq(child.lua_get("#reported"), 1)
	eq(child.lua_get("reported[1]:find('99999', 1, true) ~= nil"), true)
end

T["lifecycle"]["a collapse that unmounts before it measures sends nothing for itself"] = function()
	run([[
		reported = {}
		vim.notify = function(message) reported[#reported + 1] = message end
		Markup.animate.manual = true
		open = m.signal(false)
		view:render(m.block({ m.collapse(open, function() return m.block("inside") end) }))
		open(true)
		-- Gone before the commit it waits for.
		view:render(m.block("other"))
		reactive.flush()
		vim.wait(10)
	]])
	eq(lines(), { "other" })
	eq(child.lua_get("reported"), {})
end

T["lifecycle"]["a mount that fails leaves no nodes behind"] = function()
	run([[
		reported = 0
		vim.notify = function() reported = reported + 1 end
		bad = m.signal(false)
		view:render(m.block({
			m.show(bad, function()
				return m.block({ m.block("a"), m.block({ justify = "bogus" }) })
			end),
		}))
		before = view.engine:node_count()
		for _ = 1, 10 do
			bad(true)
			reactive.flush()
			bad(false)
			reactive.flush()
		end
		vim.wait(10)
		after = view.engine:node_count()
	]])
	eq(child.lua_get("reported"), 10)
	eq(child.lua_get("after"), child.lua_get("before"))
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

T["destroy"] = new_set()

T["destroy"]["reopening a window preserves its new contents and releases its old view"] = function()
	run([[
		host = Markup.window({ position = "right", width = 20 })
		local hosted = Markup.view(host)
		hosted:render(m.block("old"))
		weak = setmetatable({ hosted }, { __mode = "v" })
		hosted:destroy()
		host:hide()
		vim.bo[host.buf].modifiable = true
		vim.api.nvim_buf_set_lines(host.buf, 0, -1, false, { "replacement" })
		host:show()
	]])
	run([[reactive.flush(); collectgarbage("collect")]])
	eq(child.lua_get("vim.api.nvim_buf_get_lines(host.buf, 0, -1, false)"), { "replacement" })
	eq(child.lua_get("weak[1] == nil"), true)
end

T["destroy"]["a collapse closing as the view goes away writes nothing late"] = function()
	child.lua([[
		Markup.animate.manual = true
		Markup.animate.enabled = true
		errors = {}
		vim.notify = function(message) errors[#errors + 1] = message end
		open = m.signal(true)
		view = Markup.view(win)
		view:render(m.block({ m.collapse(open, m.block({ "a", "b", "c" }), { duration = 100 }) }))
		reactive.flush()
		open(false)
		reactive.flush()
		Markup.animate.tick(30)
		view:destroy()
		Markup.animate.tick(200)
		reactive.flush()
	]])
	eq(child.lua_get("errors"), {})
	eq(child.lua_get("Markup.animate.count()"), 0)
end

T["memory"] = new_set()

T["memory"]["keeps no undo history of what it draws"] = function()
	child.lua([[
		-- A buffer from elsewhere, with undo on as usual.
		vim.bo[win.buf].undolevels = 1000
		count = m.signal(0)
		view = Markup.view(win)
		view:render(m.block({ function() return ("frame %d"):format(count()) end }))
		reactive.flush()
		for i = 1, 200 do
			count(i)
			reactive.flush()
		end
		entries = #vim.fn.undotree(win.buf).entries
		undolevels = vim.bo[win.buf].undolevels
	]])
	-- Writes through the API all join one undo step, which then grows on every frame.
	eq(child.lua_get("entries"), 0)
	eq(child.lua_get("undolevels"), -1)
	eq(child.lua_get("vim.api.nvim_buf_get_lines(win.buf, 0, 1, false)[1]"), "frame 200")
end

T["cursor"] = new_set()

T["cursor"]["keeps its screen column when the text around it narrows"] = function()
	child.lua([[
		wide = m.signal(true)
		view = Markup.view(win)
		view:render(m.block({ function() return (wide() and ("█"):rep(10) or (" "):rep(10)) .. "end" end }))
		reactive.flush()
		vim.api.nvim_set_current_win(win.win)
		vim.cmd("normal! 8|")
		before = vim.fn.virtcol(".")
		wide(false)
		reactive.flush()
		after = vim.fn.virtcol(".")
	]])
	eq(child.lua_get("before"), 8)
	eq(child.lua_get("after"), 8)
end

T["cursor"]["comes back to its column when a line was short for a while"] = function()
	child.lua([[
		short = m.signal(false)
		view = Markup.view(win)
		view:render(m.block({ function() return short() and "abc" or ("x"):rep(30) end }))
		reactive.flush()
		vim.api.nvim_set_current_win(win.win)
		vim.cmd("normal! 20|")
		short(true)
		reactive.flush()
		pulled_in = vim.fn.virtcol(".")
		short(false)
		reactive.flush()
		back = vim.fn.virtcol(".")
	]])
	eq(child.lua_get("pulled_in"), 3)
	eq(child.lua_get("back"), 20)
end

T["cursor"]["stays at the end of a line after $"] = function()
	child.lua([[
		size = m.signal(10)
		view = Markup.view(win)
		view:render(m.block({ function() return ("x"):rep(size()) end }))
		reactive.flush()
		vim.api.nvim_set_current_win(win.win)
		vim.cmd("normal! $")
		size(25)
		reactive.flush()
		at = vim.fn.virtcol(".")
	]])
	eq(child.lua_get("at"), 25)
end

T["cursor"]["comes back to its row when the lines come back"] = function()
	child.lua([[
		count = m.signal(20)
		view = Markup.view(win)
		view:render(m.block(function()
			local lines = {}
			for i = 1, count() do lines[i] = m.block("row " .. i) end
			return lines
		end))
		reactive.flush()
		vim.api.nvim_set_current_win(win.win)
		vim.api.nvim_win_set_cursor(win.win, { 18, 0 })
		count(10)
		reactive.flush()
		pulled_up = vim.fn.line(".")
		count(20)
		reactive.flush()
		back = vim.fn.line(".")
	]])
	eq(child.lua_get("pulled_up"), 10)
	eq(child.lua_get("back"), 18)
end

T["cursor"]["holds its place and the scroll when lines come and go"] = function()
	child.lua([[
		count = m.signal(5)
		view = Markup.view(win)
		view:render(m.block({
			m.block(function()
				local lines = {}
				for i = 1, count() do lines[i] = m.block("top " .. i) end
				return lines
			end),
			m.block(function()
				local lines = {}
				for i = 1, 60 do lines[i] = m.block("row " .. i) end
				return lines
			end),
		}))
		reactive.flush()
		vim.api.nvim_set_current_win(win.win)
		vim.fn.winrestview({ topline = 10, lnum = 14, col = 2 })
		count(1)
		reactive.flush()
		shrunk = vim.fn.winsaveview()
		count(12)
		reactive.flush()
		grown = vim.fn.winsaveview()
	]])
	for _, name in ipairs({ "shrunk", "grown" }) do
		eq(child.lua_get(name .. ".lnum"), 14)
		eq(child.lua_get(name .. ".topline"), 10)
	end
end

T["cursor"]["a slide that is part of a page leaves a cursor elsewhere alone"] = function()
	child.lua([[
		Markup.animate.enabled = false
		page = m.signal(1)
		view = Markup.view(win)
		local rows = {}
		for i = 1, 8 do rows[i] = m.block("row " .. i) end
		view:render(m.block({
			m.slide(page, function(key) return m.block("page " .. key) end),
			rows,
		}))
		reactive.flush()
		vim.api.nvim_set_current_win(win.win)
		vim.api.nvim_win_set_cursor(win.win, { 6, 2 })
		page(2)
		reactive.flush()
		page(3)
		reactive.flush()
		cursor = vim.api.nvim_win_get_cursor(win.win)
	]])
	eq(child.lua_get("cursor"), { 6, 2 })
end

T["cursor"]["a slide that is part of a page leaves a cursor on it alone too"] = function()
	child.lua([[
		Markup.animate.enabled = false
		page = m.signal(1)
		view = Markup.view(win)
		local rows = {}
		for i = 1, 8 do rows[i] = m.block("row " .. i) end
		view:render(m.block({
			rows,
			m.slide(page, function(key)
				return m.block({ "page " .. key, "second line", "third line" })
			end),
			rows,
		}))
		reactive.flush()
		vim.api.nvim_set_current_win(win.win)
		vim.api.nvim_win_set_cursor(win.win, { 10, 3 })
		page(2)
		reactive.flush()
		on_new = vim.api.nvim_win_get_cursor(win.win)
		page(1)
		reactive.flush()
		back = vim.api.nvim_win_get_cursor(win.win)
	]])
	eq(child.lua_get("on_new"), { 10, 3 })
	eq(child.lua_get("back"), { 10, 3 })
end

T["cursor"]["a slide that is the whole view still takes the cursor back to each page"] = function()
	child.lua([[
		Markup.animate.enabled = false
		page = m.signal(1)
		view = Markup.view(win)
		view:render(m.slide(page, function(key)
			local rows = {}
			for i = 1, 8 do rows[i] = m.block(("page %d row %d"):format(key, i)) end
			return rows
		end))
		reactive.flush()
		vim.api.nvim_set_current_win(win.win)
		vim.api.nvim_win_set_cursor(win.win, { 5, 0 })
		page(2)
		reactive.flush()
		on_new = vim.api.nvim_win_get_cursor(win.win)[1]
		page(1)
		reactive.flush()
		back = vim.api.nvim_win_get_cursor(win.win)[1]
	]])
	eq(child.lua_get("on_new"), 1)
	eq(child.lua_get("back"), 5)
end

T["redraw"] = new_set()

T["redraw"]["asks for the screen when Neovim has not drawn it for a frame"] = function()
	child.lua([[
		count = m.signal(0)
		view = Markup.view(win)
		view:render(m.block({ function() return "frame " .. count() end }))
		reactive.flush()
		redraws = 0
		local cmd = vim.cmd
		vim.cmd = setmetatable({}, {
			__call = function(_, command)
				if command == "redraw" then redraws = redraws + 1 end
				return cmd(command)
			end,
			__index = cmd,
		})
		vim.wait(60, function() return false end, 5)
		count(1)
		reactive.flush()
		after_quiet = redraws
		count(2)
		reactive.flush()
		right_after = redraws
		vim.cmd = cmd
	]])
	eq(child.lua_get("after_quiet"), 1)
	-- Within a frame of the last one, it leaves the screen to Neovim.
	eq(child.lua_get("right_after"), 1)
end

T["resize"] = new_set()

T["resize"]["follows the window on the next frame even if Neovim never said"] = function()
	child.lua([[
		count = m.signal(0)
		view = Markup.view(win)
		view:render(m.block({ function() return "frame " .. count() end }))
		reactive.flush()
		before = view.engine:describe(1).outer_width
		-- As when Neovim is too busy to get round to WinResized.
		vim.o.eventignore = "WinResized"
		vim.cmd("vsplit")
		vim.api.nvim_win_set_width(win.win, 20)
		count(1)
		reactive.flush()
		after = view.engine:describe(1).outer_width
		vim.o.eventignore = ""
	]])
	eq(child.lua_get("before"), 60)
	eq(child.lua_get("after"), 20)
end

T["snap"] = T["snap"] or new_set()

T["snap"]["waits for rows the buffer does not have yet"] = function()
	child.lua([[
		errors = {}
		vim.notify = function(message) errors[#errors + 1] = message end
		view = Markup.view(win, { snap = true })
		view:render(m.block({ m.block({ "one", on_press = function() end }), m.block({ "two", on_press = function() end }) }))
		reactive.flush()
		vim.api.nvim_set_current_win(win.win)
		-- As when the engine has laid out a frame the buffer has not got yet.
		local real = view.engine
		view.engine = setmetatable({ snap = function() return 40, 0 end }, {
			__index = function(_, key)
				local value = real[key]
				if type(value) == "function" then
					return function(_, ...) return value(real, ...) end
				end
				return value
			end,
		})
		ok, err = pcall(view.snap_cursor, view)
		view.engine = real
		cursor = vim.api.nvim_win_get_cursor(win.win)
	]])
	eq(child.lua_get("ok"), true)
	eq(child.lua_get("cursor[1] <= 2"), true)
end

T["protocol"] = new_set()

T["protocol"]["a border that is not eight characters does not shift what follows"] = function()
	child.lua([[
		errors = {}
		vim.notify = function(message) errors[#errors + 1] = message end
		view = Markup.view(win)
		view:render(m.block({
			m.block({ "boxed", border = { chars = "1234567" }, width = 20 }),
			m.flex({ justify = "between", m.inline("left"), m.inline("right") }),
		}))
		reactive.flush()
		lines = vim.api.nvim_buf_get_lines(win.buf, 0, -1, false)
		box = view.engine:describe(3)
	]])
	eq(child.lua_get("errors"), {})
	-- No border, as it was not one, and the rest laid out as written.
	eq(child.lua_get("lines[1]:match('^boxed')") ~= vim.NIL, true)
	eq(child.lua_get("lines[2]:match('^left.*right$')") ~= vim.NIL, true)
end

return T
