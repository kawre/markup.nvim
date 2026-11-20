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

--- How many times a timer of 1 ms fires in `ms` here. Windows wakes timers
--- about every 15.6 ms, so no clock ticks much past 64 times a second there.
local function platform_ticks(ms)
	return child.lua_get(([[(function()
		local count, timer = 0, vim.uv.new_timer()
		timer:start(1, 1, function() count = count + 1 end)
		vim.wait(%d, function() return false end, 1)
		timer:stop()
		timer:close()
		return count
	end)()]]):format(ms))
end

--- `wanted`, or a share of what the platform can do in `ms` if that is less,
--- for the tests that a clock ticks faster than 60 times a second. A share,
--- since timers on Windows wake at 15.6 ms or twice that, from one run to the
--- next.
local function at_least(wanted, ms)
	return math.min(wanted, math.floor(platform_ticks(ms) * 0.4))
end

T["clock"] = new_set()

T["clock"]["runs as fast as the main loop allows when uncapped"] = function()
	run([[
		animate.manual = false
		animate.set_fps(math.huge)
		ticks = 0
		animate.run({ duration = 10000, update = function() ticks = ticks + 1 end })
		vim.wait(300, function() return false end, 1)
	]])
	-- At the usual 60 fps this would be about 18.
	eq(get("ticks") > at_least(30, 300), true)
end

T["clock"]["drops ticks the main loop cannot keep up with"] = function()
	run([[
		animate.manual = false
		animate.set_fps(math.huge)
		ticks = 0
		animate.run({
			duration = 10000,
			update = function()
				ticks = ticks + 1
				local until_ = vim.uv.hrtime() + 20e6
				while vim.uv.hrtime() < until_ do end
			end,
		})
		vim.wait(300, function() return false end, 1)
		started = vim.uv.hrtime()
		animate.set_fps(30)
		vim.wait(0)
		-- Nothing queued while ticks were slow, so the loop is free right away.
		waited = (vim.uv.hrtime() - started) / 1e6
	]])
	eq(get("ticks") <= 16, true)
	eq(get("waited") < 50, true)
end

T["clock"]["a new rate takes over a running clock"] = function()
	run([[
		animate.manual = false
		ticks = 0
		animate.run({ duration = 10000, update = function() ticks = ticks + 1 end })
		vim.wait(100, function() return false end, 1)
		before = ticks
		animate.set_fps(500)
		vim.wait(200, function() return false end, 1)
		after = ticks - before
	]])
	eq(get("after") > at_least(30, 200), true)
end

T["vrr"] = new_set()

local function count_ticks(code, ms)
	run(([[
		animate.manual = false
		animate.set_fps(240)
		local before = animate.ticks
		%s
		vim.wait(%d, function() return false end, 1)
		ticks = animate.ticks - before
	]]):format(code, ms))
	return get("ticks")
end

T["vrr"]["a loader ticks once per frame of its own"] = function()
	local ticks = count_ticks(
		[[
		_, owner = reactive.scope(function() frames = animate.frames({ "a", "b", "c" }, { interval = 100 }) end)
	]],
		500
	)
	-- About one a frame, five here. At 240 fps it would be about 120.
	eq(ticks >= 3, true)
	eq(ticks <= 15, true)
end

T["vrr"]["without it the clock ticks at its rate"] = function()
	local ticks = count_ticks(
		[[
		animate.vrr = false
		_, owner = reactive.scope(function() frames = animate.frames({ "a", "b", "c" }, { interval = 100 }) end)
	]],
		500
	)
	eq(ticks > at_least(40, 500), true)
end

T["vrr"]["a value with a step ticks when it crosses one and still ends on time"] = function()
	local ticks = count_ticks(
		[[
		value = animate.value(0, { duration = 400, step = 1, easing = "linear" })
		ended_at = nil
		local started = vim.uv.hrtime()
		value(4, { done = function() ended_at = (vim.uv.hrtime() - started) / 1e6 end })
	]],
		600
	)
	-- Four cells in 400 ms: a tick per half cell, not 96.
	eq(ticks <= 12, true)
	eq(get("value()"), 4)
	-- Never early. The upper bound only says it did not wait for another step,
	-- with room for a busy machine.
	eq(get("ended_at") >= 395, true)
	eq(get("ended_at") < 600, true)
end

T["vrr"]["a value without a step ticks at the rate"] = function()
	local ticks = count_ticks(
		[[
		value = animate.value(0, { duration = 300 })
		value(4)
	]],
		400
	)
	-- It ticks for the 300 ms it runs, not the whole wait.
	eq(ticks > at_least(30, 300), true)
end

T["vrr"]["something new wakes a sleeping clock"] = function()
	run([[
		animate.manual = false
		animate.set_fps(240)
		_, owner = reactive.scope(function() animate.frames({ "a", "b" }, { interval = 1000 }) end)
		vim.wait(50, function() return false end, 1)
		moved_at = nil
		local started = vim.uv.hrtime()
		animate.run({ duration = 1000, update = function() moved_at = moved_at or (vim.uv.hrtime() - started) / 1e6 end })
		vim.wait(100, function() return moved_at ~= nil end, 1)
	]])
	-- Not a second later, when the loader was next due.
	eq(get("moved_at") ~= vim.NIL and get("moved_at") < 30, true)
end

T["vrr"]["fps and vrr come from setup"] = function()
	run([[
		m.setup({ animate = { fps = 180, vrr = false } })
	]])
	eq(get("animate.fps"), 180)
	eq(get("animate.vrr"), false)
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

T["value"]["stops when its owner goes, however late it was moved"] = function()
	run([[
		_, owner = reactive.scope(function()
			value = animate.value(0, { duration = 300 })
		end)
		-- Moved from outside any scope, as a timer or an after_commit callback does.
		value(10)
		running = animate.count()
		reactive.dispose(owner)
		stopped = animate.count()
		value(20)
		after = animate.count()
	]])
	eq(get("running"), 1)
	eq(get("stopped"), 0)
	eq(get("after"), 0)
	eq(get("value()"), 20)
end

T["value"]["a stopped animation does not finish"] = function()
	run([[
		-- Each stops the other, so whichever the tick finishes first, the other
		-- must not finish after it.
		finished = {}
		local stop_a, stop_b
		stop_a = animate.run({ duration = 100, update = function() end, done = function() finished[#finished + 1] = "a"; stop_b() end })
		stop_b = animate.run({ duration = 100, update = function() end, done = function() finished[#finished + 1] = "b"; stop_a() end })
		animate.tick(200)
	]])
	local finished = get("finished")
	eq(#finished, 1)
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

-- Found by tests/test_properties.lua: a tick past the end of the loop showed
-- the first frame, wherever in the next round it landed.
T["frames land where the time is when a tick passes the end"] = function()
	run([[
		_, owner = reactive.scope(function()
			frame = m.frames({ "a", "b", "c" }, { interval = 50 })
		end)
		animate.tick(210)
		seen = frame()
		reactive.dispose(owner)
	]])
	-- 210 ms is 60 into the second round of 150: the second frame.
	eq(get("seen"), "b")
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

T["slide"]["survives the window resizing midway"] = function()
	slide("home")
	run([[
		page("next")
		reactive.flush()
		animate.tick(50)
		reactive.flush()
		vim.cmd("vnew")
		vim.api.nvim_win_set_width(win.win, 30)
	]])
	child.lua("vim.wait(20, function() return false end, 5)")
	run([[
		reactive.flush()
		animate.tick(500)
		reactive.flush()
		reactive.flush()
	]])
	eq(get("lines()"), { "top", "next" })
	-- It finished: the page that left is gone, and nothing still moves.
	eq(get("unmounts"), 1)
	eq(get("animate.running()"), false)
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

T["slide"]["pages can share keys"] = function()
	run([[
		page, pressed = m.signal("home"), nil
		local Page = m.component(function(props)
			m.use_key("x", function() pressed = props.name end)
			return m.block(props.name)
		end)
		view:render(m.slide(page, function(key)
			return Page({ name = key })
		end, { duration = 100 }))
		reactive.flush()
		page("next")
		reactive.flush()
		animate.tick(200)
		reactive.flush()
		reactive.flush()
	]])
	child.type_keys("x")
	eq(get("pressed"), "next")
end

T["keys"] = new_set()

local function shared_key()
	run([[
		pressed = nil
		first, second = m.signal(true), m.signal(true)
		local function Key(name)
			return m.component(function()
				m.use_key("x", function() pressed = name end)
				return m.block(name)
			end)
		end
		local First, Second = Key("first"), Key("second")
		view:render(m.block({
			m.show(first, function() return First() end),
			m.show(second, function() return Second() end),
		}))
		reactive.flush()
	]])
end

T["keys"]["the latest component wins"] = function()
	shared_key()
	child.type_keys("x")
	eq(get("pressed"), "second")
end

T["keys"]["removing the older one keeps the key"] = function()
	shared_key()
	run("first(false); reactive.flush()")
	child.type_keys("x")
	eq(get("pressed"), "second")
end

T["keys"]["removing the latest gives it back"] = function()
	shared_key()
	run("second(false); reactive.flush()")
	child.type_keys("x")
	eq(get("pressed"), "first")
end

T["keys"]["go away with the last component"] = function()
	shared_key()
	run("first(false); second(false); reactive.flush()")
	eq(get("vim.fn.maparg('x', 'n', false, true).buffer"), vim.NIL)
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

T["loader"] = new_set()

T["loader"]["every frame of every loader is one cell"] = function()
	run([[
		components = require("markup.view.components")
		wide = {}
		for name, loader in pairs(components.loaders) do
			for _, frame in ipairs(loader.frames) do
				if vim.api.nvim_strwidth(frame) ~= 1 then wide[#wide + 1] = name .. " " .. frame end
			end
		end
	]])
	eq(get("wide"), {})
end

T["loader"]["the snake keeps its length all the way round"] = function()
	run([[
		frames = require("markup.view.components").loaders.snake.frames
		counts = {}
		for i, frame in ipairs(frames) do
			local n, dots = vim.fn.char2nr(frame) - 0x2800, 0
			while n > 0 do
				dots = dots + n % 2
				n = math.floor(n / 2)
			end
			counts[i] = dots
		end
		distinct = #vim.fn.uniq(vim.fn.sort(vim.deepcopy(frames)))
	]])
	eq(get("#frames"), 8)
	eq(get("vim.fn.uniq(vim.fn.sort(counts))"), { 3 })
	eq(get("distinct"), 8)
end

T["loader"]["runs for as long as it is shown"] = function()
	run([[
		shown = m.signal(true)
		view:render(m.show(shown, function() return m.loader({ name = "dots" }) end))
		reactive.flush()
		first = lines()[1]
		animate.tick(90)
		reactive.flush()
		second = lines()[1]
		shown(false)
		reactive.flush()
	]])
	eq(get("first"), "⠋")
	eq(get("second"), "⠙")
	eq(get("animate.running()"), false)
end

T["loader"]["picks one at random"] = function()
	run([[
		seen = {}
		for _ = 1, 40 do
			view:render(m.loader())
			reactive.flush()
			local first = lines()[1]
			seen[first] = true
		end
		count = vim.tbl_count(seen)
	]])
	eq(get("count > 1"), true)
end

T["loader"]["names must exist"] = function()
	run([[
		ok, err = pcall(function()
			view:render(m.loader({ name = "nope" }))
			reactive.flush()
		end)
	]])
	eq(get("ok"), false)
	eq(get("tostring(err):find('unknown loader `nope`', 1, true) ~= nil"), true)
end

T["loader"]["stands still with reduced motion"] = function()
	run([[
		animate.enabled = false
		view:render(m.loader({ name = "dots" }))
		reactive.flush()
		animate.tick(500)
		reactive.flush()
	]])
	eq(get("lines()"), { "⠋" })
end

T["loader"]["every frame of a loader differs from the next"] = function()
	run([[
		repeats = {}
		for name, loader in pairs(require("markup.view.components").loaders) do
			local frames = loader.frames
			for i, frame in ipairs(frames) do
				if frame == frames[i % #frames + 1] then repeats[#repeats + 1] = name .. " " .. i end
			end
		end
	]])
	eq(get("repeats"), {})
end

T["loader"]["blooms from a dot to a flower and back"] = function()
	run([[
		view:render(m.loader({ name = "bloom" }))
		reactive.flush()
		seen = {}
		for _ = 1, 9 do
			seen[#seen + 1] = vim.fn.char2nr(lines()[1])
			animate.tick(120)
			reactive.flush()
		end
	]])
	eq(
		get("seen"),
		{ 0xF09DF, 0xF09DE, 0xF0765, 0xF09F0, 0xF024A, 0xF09F0, 0xF0765, 0xF09DE, 0xF09DF }
	)
end

T["loader"]["spinner is still a name for it"] = function()
	run([[
		view:render(m.spinner({ name = "dots" }))
		reactive.flush()
		components = require("markup.view.components")
	]])
	eq(get("lines()"), { "⠋" })
	eq(get("components.spinners == components.loaders"), true)
	eq(get("vim.deep_equal(components.spinner_names(), components.loader_names())"), true)
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
