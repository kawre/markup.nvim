---@module 'mini.test'

local new_set = MiniTest.new_set
local eq = MiniTest.expect.equality
local child = MiniTest.new_child_neovim()

local T = new_set({
	hooks = {
		pre_case = function()
			child.restart({ "-u", "scripts/minimal_init.lua" })
			child.o.lines, child.o.columns = 15, 60
			child.lua([[
				m = require("markup")
				reactive = require("markup.reactive")
				animate = Markup.animate
				animate.manual = true
				win = Markup.window({ position = "current", hijack = true, show = false, minimal = false })
				win.buf = vim.api.nvim_get_current_buf()
				win:show()
				view = Markup.view(win)
				function lines()
					return vim.tbl_map(function(line)
						return (line:gsub("%s+$", ""))
					end, vim.api.nvim_buf_get_lines(win.buf, 0, -1, false))
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

local function get(code)
	return child.lua_get(code)
end

T["value"] = new_set()

T["value"]["moves to its target over time"] = function()
	run([[
		value = m.animated(0, { duration = 100, easing = "linear" })
		value(10)
		animate.tick(50)
	]])
	eq(get("value()"), 5)

	run("animate.tick(50)")
	eq(get("value()"), 10)
	eq(get("animate.running()"), false)
end

T["value"]["waits for its delay"] = function()
	run([[
		value = m.animated(0, { duration = 100, delay = 100, easing = "linear" })
		value(10)
		animate.tick(50)
	]])
	eq(get("value()"), 0)

	run("animate.tick(100)")
	eq(get("value()"), 5)
end

T["value"]["a new target continues from where it is"] = function()
	run([[
		value = m.animated(0, { duration = 100, easing = "linear" })
		value(10)
		animate.tick(50)
		value(0)
		animate.tick(50)
	]])
	eq(get("value()"), 2.5)
end

T["value"]["drives the UI"] = function()
	run([[
		value = m.animated(0, { duration = 100, easing = "linear" })
		view:render(m.block(function() return math.floor(value()) end))
		value(10)
		animate.tick(50)
	]])
	eq(get("lines()"), { "5" })
end

T["value"]["at its target it does not start the clock"] = function()
	run([[
		done = false
		value = m.animated(5)
		value(5, { done = function() done = true end })
	]])
	eq(get("animate.running()"), false)
	eq(get("done"), true)
end

T["value"]["a zero duration applies at once"] = function()
	run([[
		value = m.animated(0)
		value(10, { duration = 0 })
	]])
	eq(get("value()"), 10)
	eq(get("animate.running()"), false)
end

T["easing"] = function()
	eq(get("animate.easing.out_cubic(1)"), 1)
	eq(get("animate.easing.in_out_cubic(0.5)"), 0.5)
	eq(get("animate.easing.out_back(0.6) > 1"), true)
end

T["reduced motion jumps to the end"] = function()
	run([[
		animate.enabled = false
		done = false
		value = m.animated(0)
		value(10, { done = function() done = true end })
	]])
	eq(get("value()"), 10)
	eq(get("done"), true)
	eq(get("animate.running()"), false)
end

T["unmounting stops animations"] = function()
	run([[
		open = m.signal(true)
		local Comp = m.component(function()
			local value = m.animated(0)
			value(10)
			return m.block("x")
		end)
		view:render(m.show(open, function() return Comp() end))
		open(false)
		reactive.flush()
	]])
	eq(get("animate.running()"), false)
end

T["the clock stops when idle"] = function()
	run([[
		animate.manual = false
		value = m.animated(0, { duration = 30 })
		value(1)
		vim.wait(500, function() return not animate.running() end, 5)
	]])
	eq(get("value()"), 1)
	eq(get("animate.running()"), false)
end

T["frames cycle for as long as they live"] = function()
	run([[
		_, owner = reactive.scope(function()
			frame = m.frames({ "a", "b" }, { interval = 100 })
		end)
		seen = { frame() }
		animate.tick(110)
		seen[2] = frame()
		animate.tick(100)
		seen[3] = frame()
		reactive.dispose(owner)
	]])
	eq(get("seen"), { "a", "b", "a" })
	eq(get("animate.running()"), false)
end

T["colors"] = new_set()

T["colors"]["mix"] = function()
	eq(get("animate.mix(0x000000, 0xff0000, 0.5)"), 0x800000)
	eq(get("animate.mix(0x102030, 0x102030, 0.7)"), 0x102030)
end

T["colors"]["highlights animate without touching layout"] = function()
	run([[
		name = animate.highlight({ fg = 0x000000 }, { fg = 0xffffff }, { duration = 100, easing = "linear" })
		animate.tick(50)
	]])
	eq(get("vim.api.nvim_get_hl(0, { name = name }).fg"), 0x808080)
end

T["colors"]["fade_in keeps the other attributes"] = function()
	run([[
		vim.api.nvim_set_hl(0, "Target", { fg = "#ffffff", bold = true })
		name = animate.fade_in("Target", 0x000000, { duration = 100 })
		animate.tick(100)
	]])
	eq(get("vim.api.nvim_get_hl(0, { name = name, link = false }).fg"), 0xffffff)
	eq(get("vim.api.nvim_get_hl(0, { name = name, link = false }).bold"), true)
end

T["colors"]["tint follows its progress both ways"] = function()
	run([[
		progress = m.signal(0)
		_, owner = reactive.scope(function()
			name = animate.tint({ bg = 0x000000 }, { bg = 0xffffff }, progress)
		end)
		progress(1)
		reactive.flush()
		up = vim.api.nvim_get_hl(0, { name = name }).bg
		progress(0)
		reactive.flush()
		down = vim.api.nvim_get_hl(0, { name = name }).bg
	]])
	eq(get("up"), 0xffffff)
	eq(get("down"), 0)
end

T["colors"]["a finished fade becomes its target"] = function()
	run([[
		vim.api.nvim_set_hl(0, "Target", { fg = "#ffffff" })
		name = animate.fade_in("Target", 0x000000, { duration = 100 })
		animate.tick(100)
		vim.api.nvim_set_hl(0, "Target", { fg = "#123456" })
	]])
	eq(get("vim.api.nvim_get_hl(0, { name = name, link = false }).fg"), 0x123456)
end

T["colors"]["names return to the pool with their owner"] = function()
	run([[
		_, owner = reactive.scope(function()
			first = animate.highlight({ fg = 0 }, { fg = 1 })
		end)
		reactive.dispose(owner)
		reactive.scope(function()
			second = animate.highlight({ fg = 0 }, { fg = 1 })
		end)
	]])
	eq(get("first == second"), true)
end

T["colors"]["half block edges follow an animated highlight"] = function()
	run([[
		vim.api.nvim_set_hl(0, "Target", { bg = "#ffffff" })
		hl = require("markup.view.hl")
		name = animate.highlight({ bg = 0x000000 }, { bg = 0xffffff }, { duration = 100, link = "Target" })
		edge = hl.edge(name)
		animate.tick(100)
	]])
	eq(get("vim.api.nvim_get_hl(0, { name = edge }).fg"), 0xffffff)
end

T["centered content wider than the window stays on screen"] = function()
	run([[
		errors = {}
		vim.notify = function(message) errors[#errors + 1] = message end
		view.commands:resize(10)
		view:render(m.vflex({
			align = "center",
			m.block({ width = 30, style = "Visual", "wide" }),
		}))
		reactive.flush()
	]])
	eq(get("errors"), {})
	eq(get("lines()"), { "wide" })
end

T["hover"] = new_set()

T["hover"]["follows the cursor"] = function()
	run([[
		seen = {}
		local function row(name)
			return m.block({
				on_press = function() end,
				on_hover = function(hovered) seen[#seen + 1] = name .. tostring(hovered) end,
				name,
			})
		end
		view:render(m.block({ row("a"), row("b") }))
		reactive.flush()
		vim.api.nvim_win_set_cursor(0, { 2, 0 })
		vim.api.nvim_exec_autocmds("CursorMoved", { buffer = win.buf })
	]])
	eq(get("seen"), { "atrue", "afalse", "btrue" })
end

T["hover"]["ends with the node"] = function()
	run([[
		seen, open = 0, m.signal(true)
		view:render(m.show(open, function()
			return m.block({ on_press = function() end, on_hover = function() seen = seen + 1 end, "a" })
		end))
		reactive.flush()
		open(false)
		reactive.flush()
	]])
	eq(get("next(view.hover_handlers)"), vim.NIL)
end

T["overflow"] = function()
	run([[
		view:render(m.block({
			m.block({ height = 1, overflow = "hidden", m.block("a"), m.block("b") }),
			m.block("c"),
		}))
	]])
	eq(get("lines()"), { "a", "c" })
end

T["collapse"] = new_set()

local function collapse(initial)
	run(([[
		open, mounts = m.signal(%s), 0
		view:render(m.block({
			m.block("top"),
			m.collapse(open, function()
				mounts = mounts + 1
				return m.block({ m.block("a"), m.block("b"), m.block("c"), m.block("d") })
			end, { duration = 100 }),
			m.block("end"),
		}))
		reactive.flush()
	]]):format(initial))
end

T["collapse"]["starts in its final state"] = function()
	collapse("true")
	eq(get("lines()"), { "top", "a", "b", "c", "d", "end" })

	collapse("false")
	eq(get("lines()"), { "top", "end" })
	eq(get("mounts"), 0)
end

T["collapse"]["opens gradually"] = function()
	collapse("false")
	run([[
		open(true)
		reactive.flush()
		animate.tick(10)
		reactive.flush()
		mid = lines()
		animate.tick(200)
		reactive.flush()
	]])
	local mid = get("mid")
	eq(#mid > 2 and #mid < 6, true)
	eq(mid[#mid], "end")
	eq(get("lines()"), { "top", "a", "b", "c", "d", "end" })
end

T["collapse"]["closes gradually and unmounts"] = function()
	collapse("true")
	run([[
		before = view.engine:node_count()
		open(false)
		reactive.flush()
		animate.tick(40)
		reactive.flush()
		mid = lines()
		animate.tick(200)
		reactive.flush()
	]])
	local mid = get("mid")
	eq(#mid > 2 and #mid < 6, true)
	eq(get("lines()"), { "top", "end" })
	eq(get("view.engine:node_count() < before"), true)
end

T["collapse"]["can change direction midway"] = function()
	collapse("true")
	run([[
		open(false)
		reactive.flush()
		animate.tick(40)
		reactive.flush()
		open(true)
		reactive.flush()
		animate.tick(300)
		reactive.flush()
		animate.tick(300)
		reactive.flush()
	]])
	eq(get("lines()"), { "top", "a", "b", "c", "d", "end" })
end

T["collapse"]["can open and close repeatedly"] = function()
	collapse("true")
	for _ = 1, 3 do
		run([[open(false); reactive.flush(); animate.tick(300); reactive.flush()]])
		eq(get("lines()"), { "top", "end" })
		run([[open(true); reactive.flush(); reactive.flush(); animate.tick(300); reactive.flush()]])
		eq(get("lines()"), { "top", "a", "b", "c", "d", "end" })
	end
end

T["collapse"]["wraps again after a resize once open"] = function()
	collapse("true")
	run([[
		view.commands:resize(30)
		view:request_commit()
		reactive.flush()
	]])
	eq(get("view.engine:describe(1).outer_width"), 30)
	eq(#get("lines()"), 6)
end

T["collapse"]["works with reduced motion"] = function()
	run("animate.enabled = false")
	collapse("true")
	run([[open(false); reactive.flush(); reactive.flush()]])
	eq(get("lines()"), { "top", "end" })

	run([[open(true); reactive.flush(); reactive.flush()]])
	eq(get("lines()"), { "top", "a", "b", "c", "d", "end" })
end

T["slide"] = new_set()

local function slide(initial)
	run(([[
		page, mounts, unmounts = m.signal(%q), 0, 0
		view:render(m.block({
			m.block("top"),
			m.slide(page, function(key)
				mounts = mounts + 1
				reactive.on_cleanup(function() unmounts = unmounts + 1 end)
				return m.block(key)
			end, {
				duration = 100,
				forward = function(_, to) return to == "next" end,
			}),
		}))
		reactive.flush()
	]]):format(initial))
end

T["slide"]["starts on its page without moving"] = function()
	slide("home")
	eq(get("lines()"), { "top", "home" })
	eq(get("animate.running()"), false)
	eq(get("mounts"), 1)
end

T["slide"]["moves the new page in from the right"] = function()
	slide("home")
	run([[
		page("next")
		reactive.flush()
		animate.tick(50)
		reactive.flush()
		reactive.flush()
		mid = lines()[2]
		animate.tick(100)
		reactive.flush()
		reactive.flush()
	]])
	eq(get("mid:find('next', 1, true) ~= nil"), true)
	eq(get("mid:find('home', 1, true)"), vim.NIL)
	eq(get("lines()"), { "top", "next" })
end

T["slide"]["unmounts the page that left"] = function()
	slide("home")
	run([[
		before = view.engine:node_count()
		page("next")
		reactive.flush()
		animate.tick(200)
		reactive.flush()
		reactive.flush()
	]])
	eq(get("mounts"), 2)
	eq(get("unmounts"), 1)
	eq(get("view.engine:node_count()"), get("before"))
end

T["slide"]["goes back the other way"] = function()
	slide("next")
	run([[
		page("home")
		reactive.flush()
		animate.tick(50)
		reactive.flush()
		reactive.flush()
		mid = lines()[2]
		animate.tick(100)
		reactive.flush()
		reactive.flush()
	]])
	-- Coming from the left, the page starts at the first column.
	eq(get("mid:find('next', 1, true) ~= nil or mid:find('home', 1, true) ~= nil"), true)
	eq(get("lines()"), { "top", "home" })
end

T["slide"]["keeps content in the window while moving"] = function()
	slide("home")
	run([[
		page("next")
		reactive.flush()
		width = vim.api.nvim_win_get_width(win.win)
		widest = 0
		for _ = 1, 8 do
			animate.tick(13)
			reactive.flush()
			reactive.flush()
			for _, line in ipairs(vim.api.nvim_buf_get_lines(win.buf, 0, -1, false)) do
				widest = math.max(widest, vim.fn.strdisplaywidth(line))
			end
		end
	]])
	eq(get("widest <= width"), true)
end

T["slide"]["can change its mind midway"] = function()
	slide("home")
	run([[
		page("next")
		reactive.flush()
		animate.tick(50)
		reactive.flush()
		page("home")
		reactive.flush()
		animate.tick(300)
		reactive.flush()
		reactive.flush()
	]])
	eq(get("lines()"), { "top", "home" })
	eq(get("animate.running()"), false)
end

T["slide"]["works with reduced motion"] = function()
	run("animate.enabled = false")
	slide("home")
	run([[page("next"); reactive.flush(); reactive.flush()]])
	eq(get("lines()"), { "top", "next" })
end

T["slide"]["follows the width of the window"] = function()
	slide("home")
	run([[
		view.width_cells(30)
		reactive.flush()
		reactive.flush()
	]])
	eq(get("view.engine:describe(1).outer_width > 0"), true)
	eq(get("lines()"), { "top", "home" })
end

T["slide"]["returns the cursor to where it was"] = function()
	run([[
		page = m.signal("home")
		rows = {}
		for i = 1, 5 do rows[i] = m.block({ on_press = function() end, "row " .. i }) end
		view = Markup.view(win, { snap = true })
		view:render(m.slide(page, function(key)
			return key == "home" and m.block(rows) or m.block({ on_press = function() end, "next" })
		end, { duration = 100 }))
		reactive.flush()
		vim.api.nvim_win_set_cursor(win.win, { 4, 0 })
		page("next")
		reactive.flush()
		animate.tick(200)
		reactive.flush()
		reactive.flush()
		on_next = vim.api.nvim_win_get_cursor(win.win)[1]
		page("home")
		reactive.flush()
		animate.tick(200)
		reactive.flush()
		reactive.flush()
	]])
	eq(get("on_next"), 1)
	eq(get("vim.api.nvim_win_get_cursor(win.win)[1]"), 4)
end

T["overflow_x"] = function()
	run([[
		view:render(m.block({
			width = 4,
			overflow_x = "hidden",
			m.block({ white_space = "nowrap", width = 10, "abcdefghij" }),
		}))
	]])
	eq(get("lines()"), { "abcd" })
end

T["overflow keeps wide content readable"] = function()
	run([[
		view:render(m.block({
			width = 4,
			overflow = "hidden",
			m.block({ white_space = "nowrap", width = 10, "abcdefghij" }),
		}))
	]])
	eq(get("lines()"), { "abcdefghij" })
end

T["progress"] = new_set()

T["progress"]["has eighths of a cell of precision"] = function()
	run([[components = require("markup.view.components")]])
	eq(get("components.bar(0, 4)"), "")
	eq(get("components.bar(1, 4)"), "████")
	eq(get("components.bar(0.5, 4)"), "██")
	eq(get("components.bar(0.53125, 4)"), "██▏")
	eq(get("components.bar(2, 2)"), "██")
end

T["progress"]["follows a value"] = function()
	run([[
		value = m.signal(0.5)
		view:render(m.block({ m.progress({ value = value, width = 4 }), m.inline("|") }))
		value(1)
		reactive.flush()
	]])
	eq(get("lines()"), { "████|" })
end

T["progress"]["keeps its width while empty"] = function()
	run([[view:render(m.block({ m.progress({ value = 0, width = 4 }), m.inline("|") }))]])
	eq(get("lines()"), { "    |" })
end

return T
