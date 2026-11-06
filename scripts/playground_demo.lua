-- markup.nvim playground demo
--
-- Edit this file and `:w` to rerender the preview below.
-- Move into the preview with <C-w>j, then use these keys:
--
--   + / -   change the counter        n / p   select a problem
--   f       cycle difficulty filter   x       mark problem solved
--   r       run a fake submission     h       show or hide the hints
--   s       toggle the stress grid    1 2 3   inspector: fiber, node, render
--                                     4       toggle debug boxes

local m = require("markup")
local hooks = m.hooks
local preview = Markup.playground.preview

-- Timers outlive a rerender, so stop the previous run's timers on every `:w`.
for _, stop in ipairs(_G.MarkupDemoTimers or {}) do
	stop()
end
_G.MarkupDemoTimers = {}

local function interval(ms, fn)
	local timer = vim.uv.new_timer()
	local function stop()
		if not timer:is_closing() then
			timer:stop()
			timer:close()
		end
	end
	timer:start(ms, ms, vim.schedule_wrap(fn))
	table.insert(_G.MarkupDemoTimers, stop)
	return stop
end

--- Binds keys for the lifetime of a component.
local function use_keys(keys)
	local win = hooks.window()
	hooks.effect(function()
		for lhs, fn in pairs(keys) do
			win:map("n", lhs, fn)
		end
	end, {})
end

local function Panel(title, children)
	return m.block({
		padding_left = 1,
		padding_right = 2,
		m.block(title, "Title"),
		m.block(("─"):rep(#title), "Comment"),
		children,
	})
end

local Counter = m.component(function()
	local count, set_count = hooks.variable(0)

	use_keys({
		["+"] = function()
			set_count(function(c)
				return c + 1
			end)
		end,
		["-"] = function()
			set_count(function(c)
				return c - 1
			end)
		end,
	})

	return Panel("Counter", {
		m.block({ m.inline("value "), m.inline(count, "Number") }),
		m.block(count % 2 == 0 and "even" or "odd", "Comment"),
	})
end)

local difficulty_hl = { Easy = "DiagnosticOk", Medium = "DiagnosticWarn", Hard = "DiagnosticError" }
local filters = { "All", "Easy", "Medium", "Hard" }
local initial_problems = {
	{ id = 1, title = "Two Sum", difficulty = "Easy" },
	{ id = 2, title = "Add Two Numbers", difficulty = "Medium" },
	{ id = 3, title = "Longest Substring", difficulty = "Medium" },
	{ id = 4, title = "Median of Two Arrays", difficulty = "Hard" },
	{ id = 20, title = "Valid Parentheses", difficulty = "Easy" },
	{ id = 42, title = "Trapping Rain Water", difficulty = "Hard" },
}

local function visible(filter)
	return vim.tbl_filter(function(p)
		return filters[filter] == "All" or p.difficulty == filters[filter]
	end, initial_problems)
end

local Problems = m.component(function()
	local filter, set_filter = hooks.variable(1)
	local selected, set_selected = hooks.variable(1)
	local solved, set_solved = hooks.variable({})
	local state = { filter = filter, selected = selected }

	-- Keymaps bind once, so they read the latest values through this table.
	local latest = hooks.variable(state)
	latest.filter, latest.selected = filter, selected

	use_keys({
		f = function()
			set_filter(function(f)
				return f % #filters + 1
			end)
			set_selected(1)
		end,
		n = function()
			set_selected(function(s)
				return math.min(s + 1, #visible(latest.filter))
			end)
		end,
		p = function()
			set_selected(function(s)
				return math.max(s - 1, 1)
			end)
		end,
		x = function()
			local problem = visible(latest.filter)[latest.selected]
			if problem then
				set_solved(function(prev)
					local next_solved = vim.deepcopy(prev)
					next_solved[problem.id] = not prev[problem.id] or nil
					return next_solved
				end)
			end
		end,
	})

	local rows = {}
	for i, problem in ipairs(visible(filter)) do
		rows[i] = m.block({
			m.inline(i == selected and "> " or "  ", "Special"),
			m.inline(solved[problem.id] and "[x] " or "[ ] ", "Comment"),
			m.inline(("%-3d "):format(problem.id), "Number"),
			m.inline(("%-22s"):format(problem.title)),
			m.inline(problem.difficulty, difficulty_hl[problem.difficulty]),
		})
	end

	return Panel("Problems: " .. filters[filter], rows)
end)

local spinner = { "|", "/", "-", "\\" }

local Runner = m.component(function()
	local status, set_status = hooks.variable("idle")
	local frame, set_frame = hooks.variable(1)
	local runs, set_runs = hooks.variable(0)
	local hints, set_hints = hooks.variable(false)

	use_keys({
		h = function()
			set_hints(function(v)
				return not v
			end)
		end,
		r = function()
			set_status("running")
			set_runs(function(n)
				return n + 1
			end)
			local ticks = 0
			local stop
			stop = interval(80, function()
				ticks = ticks + 1
				set_frame(function(f)
					return f % #spinner + 1
				end)
				if ticks == 15 then
					stop()
					set_status(math.random() > 0.3 and "accepted" or "wrong")
				end
			end)
		end,
	})

	local line
	if status == "running" then
		line = m.block(spinner[frame] .. " Judging...", "DiagnosticInfo")
	elseif status == "accepted" then
		line = m.block("Accepted  63/63 cases, 0 ms", "DiagnosticOk")
	elseif status == "wrong" then
		line = m.block("Wrong Answer  41/63 cases", "DiagnosticError")
	else
		line = m.block("Press r to run", "Comment")
	end

	return Panel("Console", {
		line,
		m.block({ m.inline("runs "), m.inline(runs, "Number") }),
		hints and m.block("Hint: try a hash map.", "DiagnosticHint") or false,
	})
end)

local Stress = m.component(function()
	local running, set_running = hooks.variable(false)
	local tick, set_tick = hooks.variable(0)
	local stop_ref = hooks.variable({})

	use_keys({
		s = function()
			if stop_ref.stop then
				stop_ref.stop()
				stop_ref.stop = nil
				set_running(false)
			else
				set_running(true)
				stop_ref.stop = interval(16, function()
					set_tick(function(t)
						return t + 1
					end)
				end)
			end
		end,
	})

	local cells = {}
	for row = 1, 6 do
		local cols = {}
		for col = 1, 10 do
			local value = (tick + row * col) % 100
			cols[col] = m.inline(
				("%02d "):format(value),
				value < 33 and "String" or value < 66 and "Function" or "Label"
			)
		end
		cells[row] = m.block(cols)
	end

	local fps = preview.stats and preview.stats.fps or 0
	return Panel("Stress", {
		m.block({
			m.inline(running and "running " or "stopped ", running and "DiagnosticOk" or "Comment"),
			m.inline(("%d fps"):format(fps), "Number"),
		}),
		cells,
	})
end)

local App = m.component(function()
	return m.block({
		spacing = 1,
		m.block("markup.nvim playground", "Title"),
		m.flex({ Counter(), Runner(), Stress() }),
		Problems(),
	})
end)

preview:render(App)
