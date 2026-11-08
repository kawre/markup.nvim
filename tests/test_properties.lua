---@module 'mini.test'

--- Property tests: rules that must hold for any input, checked on many random
--- ones. Each seed replays exactly, and a failure says which seed broke what.

local new_set = MiniTest.new_set
local eq = MiniTest.expect.equality
local child = MiniTest.new_child_neovim()

local SEEDS = tonumber(vim.env.PROPERTY_SEEDS) or 25

local function seeds(from)
	local list = {}
	for i = 1, SEEDS do
		list[i] = { from + i }
	end
	return list
end

local T = new_set({
	hooks = {
		pre_case = function()
			child.restart({ "-u", "scripts/minimal_init.lua" })
			child.o.lines, child.o.columns = 30, 80
			child.lua([[
				m = require("markup")
				reactive = require("markup.reactive")
				F = dofile("tests/helpers/fuzz.lua")
				F.capture()
			]])
		end,
		post_once = function()
			child.stop()
		end,
	},
})

--- Runs `code` in the child with the seed as `...`, returning the global
--- `failure` it leaves, nil when every property held.
local function check(code, seed)
	child.lua("failure = nil\n" .. code, { seed })
	return child.lua_get("failure")
end

-- Reactivity -----------------------------------------------------------------

T["reactive"] = new_set({ parametrize = seeds(0) })

T["reactive"]["a random graph agrees with plain recomputation"] = function(seed)
	eq(
		check(
			[[
		local seed = ...
		local r = F.rng(seed)
		local function fail(message, ...)
			failure = failure or ("seed %d: " .. message):format(seed, ...)
		end

		-- Nodes of the graph. `pure` computes the same value from the signal
		-- values alone, which is what everything must agree with.
		local nodes, signals = {}, {}
		for i = 1, 6 do
			local signal = reactive.signal(r.int(0, 3))
			signals[i] = signal
			nodes[i] = { read = signal, pure = function(env) return env[i] end, deps = { [i] = true } }
		end

		local memo_runs, flushes = {}, 0
		for j = 1, 10 do
			local a, b, c = r.int(1, #nodes), r.int(1, #nodes), r.int(1, #nodes)
			local A, B, C = nodes[a], nodes[b], nodes[c]
			local deps = vim.tbl_extend("force", {}, A.deps, B.deps, C.deps)
			local node = { deps = deps }
			if r.chance(0.5) then
				-- What it reads depends on a value, so its dependencies move.
				node.pure = function(env)
					if A.pure(env) > 1 then return B.pure(env) end
					return C.pure(env)
				end
				node.read = reactive.memo(function()
					memo_runs[j] = (memo_runs[j] or 0) + 1
					if A.read() > 1 then return B.read() end
					return C.read()
				end)
			else
				node.pure = function(env) return A.pure(env) + B.pure(env) * 2 - C.pure(env) end
				node.read = reactive.memo(function()
					memo_runs[j] = (memo_runs[j] or 0) + 1
					return A.read() + B.read() * 2 - C.read()
				end)
			end
			node.memo = j
			nodes[#nodes + 1] = node
		end

		local function env()
			local values = {}
			for i, signal in ipairs(signals) do
				values[i] = reactive.untrack(signal)
			end
			return values
		end

		local base = reactive.stats()
		local effects = {}
		local _, owner = reactive.scope(function()
			for k = 1, 8 do
				local reads = {}
				for _ = 1, r.int(1, 3) do
					reads[#reads + 1] = nodes[r.int(1, #nodes)]
				end
				local effect = { runs = 0, deps = {} }
				for _, node in ipairs(reads) do
					effect.deps = vim.tbl_extend("force", effect.deps, node.deps)
				end
				reactive.effect(function()
					effect.runs = effect.runs + 1
					local now = env()
					local seen = {}
					for i, node in ipairs(reads) do
						seen[i] = node.read()
						-- Glitch free: never a mix of old and new values.
						if seen[i] ~= node.pure(now) then
							fail("effect %d saw %s, the signals make it %s", k, tostring(seen[i]), tostring(node.pure(now)))
						end
					end
					effect.seen, effect.reads = seen, reads
				end)
				effects[k] = effect
			end
		end)

		for step = 1, 60 do
			if failure then break end
			-- Written with a new value, even if a later write puts the old one
			-- back: effects are queued on the write, not on the final value.
			local changed = {}
			for _ = 1, r.int(1, 3) do
				local i, value = r.int(1, #signals), r.int(0, 3)
				changed[i] = changed[i] or reactive.untrack(signals[i]) ~= value
				signals[i](value)
			end
			local after = env()

			local runs = {}
			for k, effect in ipairs(effects) do runs[k] = effect.runs end
			local memo_before = vim.deepcopy(memo_runs)
			reactive.flush()

			for k, effect in ipairs(effects) do
				local ran = effect.runs - runs[k]
				if ran > 1 then
					fail("step %d: effect %d ran %d times in one flush", step, k, ran)
				end
				-- It only runs when something it can read changed.
				local cause = false
				for i in pairs(effect.deps) do
					cause = cause or changed[i]
				end
				if ran > 0 and not cause then
					fail("step %d: effect %d ran with nothing it reads written", step, k)
				end
				for i, node in ipairs(effect.reads) do
					if effect.seen[i] ~= node.pure(after) then
						fail("step %d: effect %d holds %s, the signals make it %s", step, k, tostring(effect.seen[i]), tostring(node.pure(after)))
					end
				end
			end
			for j, count in pairs(memo_runs) do
				if count - (memo_before[j] or 0) > 1 then
					fail("step %d: memo %d computed %d times in one flush", step, j, count - (memo_before[j] or 0))
				end
			end
		end

		-- Disposing the scope stops every effect and frees what it counted.
		reactive.dispose(owner)
		local runs = 0
		for _, effect in ipairs(effects) do runs = runs + effect.runs end
		for i = 1, #signals do signals[i](function(v) return v + 10 end) end
		reactive.flush()
		local after = 0
		for _, effect in ipairs(effects) do after = after + effect.runs end
		if after ~= runs then
			fail("%d effect runs after their scope was disposed", after - runs)
		end
		local stats = reactive.stats()
		if stats.effects ~= base.effects then
			fail("%d effects still alive after dispose", stats.effects - base.effects)
		end
		if #F.errors > 0 then
			fail("reported %s", F.errors[1])
		end
	]],
			seed
		),
		vim.NIL
	)
end

T["reactive"]["effects that write signals settle on the plain values"] = function(seed)
	eq(
		check(
			[[
		local seed = ...
		local r = F.rng(seed)
		-- A chain of effects, each writing the next signal from the one before.
		local chain = {}
		for i = 1, 8 do chain[i] = reactive.signal(0) end
		local factor = {}
		for i = 1, 7 do
			factor[i] = r.int(1, 3)
			reactive.effect(function()
				chain[i + 1](chain[i]() * factor[i] % 97)
			end)
		end
		local seen
		reactive.effect(function() seen = chain[8]() end)
		for step = 1, 40 do
			local start = r.int(0, 50)
			chain[1](start)
			reactive.flush()
			local expected = start
			for i = 1, 7 do expected = expected * factor[i] % 97 end
			if seen ~= expected then
				failure = ("seed %d, step %d: the chain ends at %s, plainly %d"):format(seed, step, tostring(seen), expected)
				break
			end
		end
	]],
			seed
		),
		vim.NIL
	)
end

-- Animation ------------------------------------------------------------------

T["animate"] = new_set({ parametrize = seeds(100) })

--- Ticks adding up to `total`, cut at random.
local SPLIT = [[
	local function split(r, total)
		local ticks, left = {}, total
		while left > 0 do
			local tick = math.min(left, r.pick({ 1, 3, 7, 16, 17, 33, 50, 120 }))
			ticks[#ticks + 1] = tick
			left = left - tick
		end
		return ticks
	end
]]

T["animate"]["a value lands on its target however time is cut"] = function(seed)
	eq(
		check(SPLIT .. [[
		local seed = ...
		local r = F.rng(seed)
		local animate = Markup.animate
		animate.manual = true
		local easings = { "linear", "out_quad", "out_cubic", "out_quint", "in_out_cubic" }

		for case = 1, 10 do
			local from, to = r.int(-50, 50), r.int(-50, 50)
			local duration, delay = r.int(1, 400), r.chance(0.3) and r.int(1, 100) or nil
			local easing = r.pick(easings)
			local done = 0
			local value = animate.value(from, { duration = duration, delay = delay, easing = easing })
			value(to, { done = function() done = done + 1 end })

			local previous = from
			for _, tick in ipairs(split(r, duration + (delay or 0) + r.int(0, 50))) do
				animate.tick(tick)
				local now = value()
				-- These easings never overshoot, so it only ever moves towards the target.
				local towards = (to - from) * (now - previous) >= -1e-9
				local inside = math.min(from, to) - 1e-9 <= now and now <= math.max(from, to) + 1e-9
				if not (towards and inside) then
					failure = ("seed %d, case %d: %s from %d to %d went to %s after %s"):format(seed, case, easing, from, to, tostring(now), tostring(previous))
					return
				end
				previous = now
			end
			if value() ~= to or done ~= 1 then
				failure = ("seed %d, case %d: ended at %s, done %d times, wanted %d once"):format(seed, case, tostring(value()), done, to)
				return
			end
			if animate.running() then
				failure = ("seed %d, case %d: still running after it ended"):format(seed, case)
				return
			end
		end
	]], seed),
		vim.NIL
	)
end

T["animate"]["the same time gives the same value, cut into any ticks"] = function(seed)
	eq(
		check(SPLIT .. [[
		local seed = ...
		local r = F.rng(seed)
		local animate = Markup.animate
		animate.manual = true
		for case = 1, 10 do
			local duration = r.int(10, 500)
			local at = r.int(0, duration - 1)
			local results = {}
			for attempt = 1, 2 do
				local value = animate.value(0, { duration = duration, easing = "in_out_cubic" })
				value(1000)
				for _, tick in ipairs(split(r, at)) do animate.tick(tick) end
				results[attempt] = value()
				value(1000, { duration = 0 })
			end
			if math.abs(results[1] - results[2]) > 1e-6 then
				failure = ("seed %d, case %d: at %d ms of %d it is %s one way and %s the other"):format(seed, case, at, duration, results[1], results[2])
				return
			end
		end
	]], seed),
		vim.NIL
	)
end

T["animate"]["frames show the frame of the time, however time is cut"] = function(seed)
	eq(
		check(SPLIT .. [[
		local seed = ...
		local r = F.rng(seed)
		local animate = Markup.animate
		animate.manual = true
		for case = 1, 10 do
			local count, interval = r.int(2, 6), r.pick({ 20, 50, 80, 100 })
			local values = {}
			for i = 1, count do values[i] = i end
			local frame
			local _, owner = reactive.scope(function()
				frame = animate.frames(values, { interval = interval })
			end)
			local elapsed = 0
			for _, tick in ipairs(split(r, r.int(1, count * interval * 4))) do
				animate.tick(tick)
				elapsed = elapsed + tick
				local expected = math.floor(elapsed / interval) % count + 1
				if frame() ~= expected then
					failure = ("seed %d, case %d: %d frames of %d ms show frame %d at %d ms, not %d"):format(seed, case, count, interval, frame(), elapsed, expected)
					reactive.dispose(owner)
					return
				end
			end
			reactive.dispose(owner)
			if animate.running() then
				failure = ("seed %d, case %d: frames still run after their owner went"):format(seed, case)
				return
			end
		end
	]], seed),
		vim.NIL
	)
end

-- Windows --------------------------------------------------------------------

T["window"] = new_set({ parametrize = seeds(200) })

T["window"]["dimming follows the popups still open, in any order"] = function(seed)
	eq(
		check(
			[[
		local seed = ...
		local r = F.rng(seed)
		vim.o.termguicolors = true
		vim.api.nvim_set_hl(0, "Normal", { fg = "#cdd6f4", bg = "#1e1e2e" })
		local api = vim.api

		-- Floats that are not popups, which the popups dim too.
		local plain = {}
		for i = 1, 2 do
			plain[i] = api.nvim_open_win(api.nvim_create_buf(false, true), false, {
				relative = "editor", row = i, col = i, width = 10, height = 2, zindex = 10 + i,
			})
		end

		-- The model: popups in the order they opened, each with the windows
		-- that were there to dim when it did, and what each window had of its
		-- own before anything dimmed it.
		local open, own = {}, {}
		local function floats()
			local list = {}
			for _, win in ipairs(api.nvim_tabpage_list_wins(0)) do
				if api.nvim_win_get_config(win).relative ~= "" then
					list[#list + 1] = win
				end
			end
			return list
		end

		for step = 1, 30 do
			if #open == 0 or (#open < 4 and r.chance(0.55)) then
				local before = floats()
				for _, win in ipairs(before) do
					local dimmed = false
					for _, entry in ipairs(open) do dimmed = dimmed or entry.dimmed[win] ~= nil end
					if not dimmed then own[win] = api.nvim_get_hl_ns({ winid = win }) end
				end
				local popup = Markup.window({
					width = 0.3, height = 0.3, dim = r.pick({ true, 0.3, 0.6 }), enter = true,
				})
				local dimmed = {}
				for _, win in ipairs(before) do dimmed[win] = true end
				open[#open + 1] = { popup = popup, dimmed = dimmed }
			else
				local index = r.int(1, #open)
				open[index].popup:close()
				table.remove(open, index)
			end

			for _, win in ipairs(floats()) do
				local expected
				for i = #open, 1, -1 do
					if open[i].dimmed[win] then
						expected = open[i].popup.dimmed[win]
						break
					end
				end
				local actual = api.nvim_get_hl_ns({ winid = win })
				-- Undimmed, a window has what it had, where -1 and 0 both mean nothing.
				local mine = own[win] and math.max(own[win], 0)
				if expected == nil and mine ~= nil and math.max(actual, 0) ~= mine then
					failure = ("seed %d, step %d: window %d has namespace %d, its own is %d"):format(seed, step, win, actual, mine)
					return
				elseif expected ~= nil and actual ~= expected then
					failure = ("seed %d, step %d: window %d has namespace %d, the popups still open make it %d"):format(seed, step, win, actual, expected)
					return
				end
			end
		end

		while #open > 0 do
			table.remove(open).popup:close()
		end
		for _, win in ipairs(floats()) do
			if own[win] and math.max(api.nvim_get_hl_ns({ winid = win }), 0) ~= math.max(own[win], 0) then
				failure = ("seed %d: window %d did not get its own namespace back"):format(seed, win)
				return
			end
			if vim.bo[api.nvim_win_get_buf(win)].filetype == "markup_backdrop" then
				failure = ("seed %d: a backdrop outlived its popup"):format(seed)
				return
			end
		end
	]],
			seed
		),
		vim.NIL
	)
end

-- Picker ---------------------------------------------------------------------

T["picker"] = new_set({ parametrize = seeds(300) })

T["picker"]["highlights split a label without losing a character"] = function(seed)
	eq(
		check(
			[[
		local seed = ...
		local r = F.rng(seed)
		local picker = require("markup.picker")
		local chars = { "a", "b", "Z", " ", "-", "é", "日", "🙂", "e\u{301}" }
		for case = 1, 50 do
			local label = ""
			for _ = 1, r.int(0, 12) do label = label .. r.pick(chars) end
			-- Characters as `matchfuzzypos` counts them, accents with their letter.
			local count = #vim.fn.split(label, "\\zs")
			local positions = {}
			for i = 0, count - 1 do
				if r.chance(0.4) then positions[#positions + 1] = i end
			end
			local spans = picker.highlight(label, positions)
			local joined, marked = "", 0
			for _, span in ipairs(spans) do
				joined = joined .. span[1]
				if span[2] then marked = marked + #vim.fn.split(span[1], "\\zs") end
			end
			if joined ~= label or marked ~= #positions then
				failure = ("seed %d: %q with %s became %s"):format(seed, label, vim.inspect(positions), vim.inspect(spans))
				return
			end
		end
	]],
			seed
		),
		vim.NIL
	)
end

T["picker"]["filtering keeps only items the query matches, in order of the query"] = function(seed)
	eq(
		check(
			[[
		local seed = ...
		local r = F.rng(seed)
		local picker = require("markup.picker")
		local words = { "apple", "Banana", "cherry", "date", "elder berry", "fig", "grape", "日本", "naïve" }
		local items = {}
		for i = 1, 30 do
			items[i] = { label = r.pick(words) .. " " .. r.pick(words), value = i, keywords = r.chance(0.3) and r.pick(words) or nil }
		end
		local all = picker.filter(items, "  ")
		if #all ~= #items then
			failure = ("seed %d: a blank query kept %d of %d"):format(seed, #all, #items)
			return
		end
		for i, entry in ipairs(all) do
			if entry.item ~= items[i] then
				failure = ("seed %d: a blank query moved item %d"):format(seed, i)
				return
			end
		end
		for _ = 1, 20 do
			local query = r.pick({ "a", "an", "ry", "e b", "zz", "日", "AP" })
			local seen = {}
			for _, entry in ipairs(picker.filter(items, query)) do
				if seen[entry.item] then
					failure = ("seed %d: %q listed an item twice"):format(seed, query)
					return
				end
				seen[entry.item] = true
				local label = entry.item.label
				local length = vim.fn.strchars(label)
				for _, position in ipairs(entry.positions or {}) do
					if position >= length + 1 + vim.fn.strchars(entry.item.keywords or "") then
						failure = ("seed %d: %q matched past the end of %q"):format(seed, query, label)
						return
					end
				end
			end
		end
	]],
			seed
		),
		vim.NIL
	)
end

-- Text -----------------------------------------------------------------------

T["text"] = new_set({ parametrize = seeds(400) })

T["text"]["wrapping keeps every character and stays inside the box"] = function(seed)
	eq(
		check(
			[[
		local seed = ...
		local r = F.rng(seed)
		local win = Markup.window({ position = "current", show = false, minimal = false })
		win.buf = vim.api.nvim_get_current_buf()
		win:show()
		local view = Markup.view(win)
		local words = { "a", "to", "word", "longer", "日本語", "é", "🙂", "averyveryverylongword", "x-y" }
		for case = 1, 20 do
			local parts = {}
			for _ = 1, r.int(1, 15) do parts[#parts + 1] = r.pick(words) end
			local text = table.concat(parts, " ")
			local width = r.int(4, 40)
			view:render(m.block({ width = width, text }))
			local lines = vim.api.nvim_buf_get_lines(win.buf, 0, -1, false)
			for _, line in ipairs(lines) do
				if vim.fn.strdisplaywidth(line) > width then
					failure = ("seed %d: %q at width %d drew %q, %d wide"):format(seed, text, width, line, vim.fn.strdisplaywidth(line))
					return
				end
			end
			local drawn = table.concat(lines, ""):gsub(" ", "")
			local wanted = text:gsub(" ", "")
			if drawn ~= wanted then
				failure = ("seed %d: %q at width %d drew %s"):format(seed, text, width, vim.inspect(lines))
				return
			end

			-- Without wrapping it is one line, exactly the text.
			view:render(m.block({ width = width, white_space = "nowrap", text }))
			local line = vim.api.nvim_buf_get_lines(win.buf, 0, -1, false)
			if #line ~= 1 or line[1]:gsub("%s+$", "") ~= text then
				failure = ("seed %d: %q without wrapping drew %s"):format(seed, text, vim.inspect(line))
				return
			end
		end
	]],
			seed
		),
		vim.NIL
	)
end

return T
