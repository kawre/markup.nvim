--- Time based values.
---
--- One clock drives every animation and only runs while something moves, so an
--- idle UI costs nothing. With `vrr` on it also skips ticks that could not
--- change anything, waking when the next animation is due to move: a loader
--- ticks once per frame of its own, a value with a `step` once per step, and
--- `fps` becomes the most the clock ever ticks. Animations belong to the current owner, which means
--- unmounting a component stops whatever it started.

local reactive = require("markup.reactive")
local hl = require("markup.view.hl")

---@class markup.animate
local M = {
	--- Set to false for reduced motion: everything jumps to its end.
	enabled = true,
	fps = 60,
	--- Tick only when an animation can change, rather than `fps` times a second.
	vrr = true,
	--- Ticks since startup, for devtools.
	ticks = 0,
	--- With this set the clock stands still until `tick` is called.
	manual = false,
}

---@alias markup.easing fun(t: number): number

---@type table<string, markup.easing>
M.easing = {
	linear = function(t)
		return t
	end,
	out_quad = function(t)
		return 1 - (1 - t) ^ 2
	end,
	out_cubic = function(t)
		return 1 - (1 - t) ^ 3
	end,
	out_quint = function(t)
		return 1 - (1 - t) ^ 5
	end,
	in_out_cubic = function(t)
		return t < 0.5 and 4 * t ^ 3 or 1 - (-2 * t + 2) ^ 3 / 2
	end,
	out_back = function(t)
		local c = 1.70158
		return 1 + (c + 1) * (t - 1) ^ 3 + c * (t - 1) ^ 2
	end,
}

---@class markup.animate.opts
---@field duration? number ms, 300 by default
---@field delay? number ms
---@field easing? string|markup.easing `out_cubic` by default
---@field loop? boolean restart when finished
---@field update fun(progress: number) called with the eased progress
---@field done? fun()

---@class markup.animation
---@field elapsed number
---@field opts markup.animate.opts

local active = {} ---@type table<markup.animation, boolean>
local timer ---@type uv.uv_timer_t?
local last_tick = 0
local ticking = false

local function now()
	return vim.uv.hrtime() / 1e6
end

local function stop_clock()
	if timer and not timer:is_closing() then
		timer:stop()
		timer:close()
	end
	timer = nil
end

local function interval()
	return math.max(math.floor(1000 / M.fps), 1)
end

local due = 0 -- when the clock wakes next
local schedule
local in_tick = false
local deferred, deferred_order = {}, {} -- jobs waiting for the next tick

--- How long until `animation` could look different, or nil when it can change
--- on any tick.
---@param animation table
---@return number?
local function wait_for(animation)
	local opts = animation.opts
	local running = animation.elapsed - (opts.delay or 0)
	if running < 0 then
		return -running
	end
	if opts.next then
		return opts.next(running)
	end
	if opts.step and opts.at then
		local duration = opts.duration or 300
		local remaining = duration - running
		if remaining <= 0 then
			return 0
		end
		-- Half a step, so whether it is rounded or floored the change is never late.
		local half = opts.step / 2
		local function quantum(at)
			return math.floor(opts.at(animation.ease(math.min(at / duration, 1))) / half)
		end
		local current = quantum(running)
		for ms = 1, math.ceil(remaining) do
			if quantum(running + ms) ~= current then
				return ms
			end
		end
		return remaining
	end
	return nil
end

--- The time to sleep before the next tick.
local function next_wait()
	local least = interval()
	if not M.vrr then
		return least
	end
	local wait = math.huge
	for animation in pairs(active) do
		local until_change = wait_for(animation)
		if not until_change then
			return least
		end
		wait = math.min(wait, until_change)
	end
	if wait == math.huge then
		return least
	end
	-- Timers count whole milliseconds, rounded down, so one more keeps the
	-- wake from landing just before the change.
	return math.max(math.ceil(wait) + 1, least)
end

schedule = function(wait)
	-- Timers count from the loop's cached time, which can be behind, and then
	-- wake before the change they are waiting for.
	vim.uv.update_time()
	due = now() + wait
	timer:stop()
	timer:start(wait, 0, function()
		-- A tick slower than the interval would otherwise queue up more ticks
		-- than the main loop can ever run.
		if ticking then
			return
		end
		ticking = true
		vim.schedule(function()
			ticking = false
			if not timer then
				return
			end
			local current = now()
			M.tick(current - last_tick)
			last_tick = current
			if timer then
				schedule(next_wait())
			end
		end)
	end)
end

local function start_clock()
	if M.manual then
		return
	end
	if timer then
		-- A sleeping clock wakes for what just started, if that is sooner.
		if due - now() > interval() and not ticking then
			schedule(interval())
		end
		return
	end

	last_tick = now()
	timer = vim.uv.new_timer()
	schedule(interval())
end

--- Changes how many frames a second animations move at, `math.huge` for as
--- many as the main loop can run.
---@param fps number
function M.set_fps(fps)
	M.fps = fps
	if timer then
		stop_clock()
		start_clock()
	end
end

local function ease_of(opts)
	local easing = opts.easing or "out_cubic"
	if type(easing) == "function" then
		return easing
	end
	return M.easing[easing] or error(("unknown easing `%s`"):format(tostring(easing)), 0)
end

--- Moves every animation forward.
---@param ms number
function M.tick(ms)
	M.ticks = M.ticks + 1
	in_tick = true
	local finished = {}

	for animation in pairs(active) do
		local opts = animation.opts
		animation.elapsed = animation.elapsed + ms

		local running = animation.elapsed - (opts.delay or 0)
		if running >= 0 then
			local duration = opts.duration or 300
			local t = duration > 0 and math.min(running / duration, 1) or 1

			if t >= 1 and opts.loop then
				-- Where the loop is now, not its start: a tick that passes the end
				-- lands part of the way into the next round.
				local into = duration > 0 and running % duration or 0
				animation.elapsed = (opts.delay or 0) + into
				opts.update(animation.ease(duration > 0 and into / duration or 0))
			else
				opts.update(animation.ease(t))
				if t >= 1 then
					finished[#finished + 1] = animation
				end
			end
		end
	end

	for _, animation in ipairs(finished) do
		-- One finishing can stop another, which then must not finish too.
		if active[animation] then
			active[animation] = nil
			if animation.opts.done then
				animation.opts.done()
			end
		end
	end

	reactive.flush()

	-- What waited for this frame goes with it.
	local jobs = deferred_order
	deferred, deferred_order = {}, {}
	for _, job in ipairs(jobs) do
		job()
	end
	in_tick = false

	if next(active) == nil then
		stop_clock()
	end
end

--- Holds `job` for the next tick, when the clock is due to tick within a frame,
--- so what changes between frames is drawn with the frame rather than on its
--- own. Returns false when it is not: the caller runs `job` itself.
---@param job function
---@return boolean held
function M.hold_for_frame(job)
	if in_tick or M.manual or not timer or reactive.forced() then
		return false
	end
	-- A frame away, with room for the timer's own lateness: a clock that sleeps
	-- longer, waiting for a loader's next frame, does not hold anything up.
	if not ticking and due - now() > math.max(interval(), 16) + 4 then
		return false
	end
	if not deferred[job] then
		deferred[job] = true
		deferred_order[#deferred_order + 1] = job
	end
	return true
end

--- Whether anything is moving.
---@return boolean
function M.running()
	return next(active) ~= nil
end

--- How many animations are moving.
---@return integer
function M.count()
	local count = 0
	for _ in pairs(active) do
		count = count + 1
	end
	return count
end

--- Starts an animation, returning a function that stops it.
---@param opts markup.animate.opts
---@return function stop
function M.run(opts)
	local animation = { elapsed = 0, opts = opts, ease = ease_of(opts) }

	local function stop()
		active[animation] = nil
	end

	-- Without a duration there is nothing to wait for, so it must not take a tick.
	if not M.enabled or (opts.duration == 0 and not opts.delay) then
		if not opts.loop then
			opts.update(animation.ease(1))
			if opts.done then
				opts.done()
			end
		end
		return stop
	end

	active[animation] = true
	reactive.on_cleanup(stop)
	start_clock()
	return stop
end

--- A number that moves to a new target instead of jumping to it. Reads and
--- writes like a signal.
---@param initial number
---@param defaults? { duration?: number, delay?: number, easing?: string|markup.easing, step?: number }
--- `step` is the least change that shows, such as 1 for a value drawn in whole
--- cells, so the clock can sleep until the value next crosses one.
---@return fun(target?: number, opts?: table): number
function M.value(initial, defaults)
	local current = reactive.signal(initial)
	local stop
	local disposed = false

	-- It belongs to where it was made, however late it is told to move: a value
	-- moved from a timer or after a commit still stops when its owner goes.
	if reactive.current_owner() then
		reactive.on_cleanup(function()
			disposed = true
			if stop then
				stop()
				stop = nil
			end
		end)
	end

	return function(...)
		if select("#", ...) == 0 then
			return current()
		end

		local target, opts = ...
		if stop then
			stop()
		end
		if disposed then
			current(target)
			return target
		end

		local from = reactive.untrack(current)
		local settings = vim.tbl_extend("force", defaults or {}, opts or {})

		-- Already there: nothing moves, so the clock can stay off.
		if from == target then
			if settings.done then
				settings.done()
			end
			return target
		end

		settings.at = function(progress)
			return from + (target - from) * progress
		end
		settings.update = function(progress)
			current(settings.at(progress))
		end
		stop = M.run(settings)
		return target
	end
end

--- Cycles through values for as long as the owner lives.
---@generic T
---@param values T[]
---@param opts? { interval?: number }
---@return fun(): T
function M.frames(values, opts)
	local index = reactive.signal(1)
	local interval = opts and opts.interval or 80

	M.run({
		duration = interval * #values,
		easing = "linear",
		loop = true,
		next = function(running)
			return interval - running % interval
		end,
		update = function(progress)
			index(math.min(math.floor(progress * #values) + 1, #values))
		end,
	})

	return function()
		return values[index()]
	end
end

local function channels(color)
	return math.floor(color / 65536) % 256, math.floor(color / 256) % 256, color % 256
end

--- Blends two colors, given as numbers.
---@param from integer
---@param to integer
---@param t number
---@return integer
function M.mix(from, to, t)
	local r1, g1, b1 = channels(from)
	local r2, g2, b2 = channels(to)
	local function blend(a, b)
		return math.floor(a + (b - a) * t + 0.5)
	end
	return blend(r1, r2) * 65536 + blend(g1, g2) * 256 + blend(b1, b2)
end

--- A color from a highlight, as a number.
---@param group string
---@param attribute "fg"|"bg"
---@return integer?
function M.color(group, attribute)
	return vim.api.nvim_get_hl(0, { name = group, link = false })[attribute]
end

local free_groups = {} ---@type string[]
local groups = 0

---@param name string
---@param definition vim.api.keyset.highlight
local function set_highlight(name, definition)
	vim.api.nvim_set_hl(0, name, definition)
	hl.sync_edge(name)
end

--- Neovim cannot delete highlights, so names are reused once their owner goes.
---@return string
local function acquire_group()
	local name = table.remove(free_groups)
	if not name then
		groups = groups + 1
		name = ("MarkupAnimated%d"):format(groups)
	end

	reactive.on_cleanup(function()
		free_groups[#free_groups + 1] = name
	end)
	return name
end

local function blended(from, to, base)
	local definition = vim.deepcopy(base or {})
	return function(t)
		for _, attribute in ipairs({ "fg", "bg" }) do
			if from[attribute] and to[attribute] then
				definition[attribute] = M.mix(from[attribute], to[attribute], t)
			end
		end
		return definition
	end
end

--- A new highlight that animates from `from` to `to`, which are tables of
--- colors in the form `{ fg = 0xrrggbb, bg = 0xrrggbb }`. Runs without touching
--- the layout, so it is the cheapest animation there is.
---@param from table
---@param to table
---@param opts? markup.animate.opts|{ base?: table, link?: string } `link` is the
--- group to become at the end, which then follows colorscheme changes
---@return string name
function M.highlight(from, to, opts)
	opts = vim.tbl_extend("force", {}, opts or {})
	local name = acquire_group()
	local at = blended(from, to, opts.base)

	set_highlight(name, at(0))

	opts.update = function(progress)
		set_highlight(name, at(progress))
	end

	local done = opts.done
	opts.done = function()
		if opts.link then
			set_highlight(name, { link = opts.link })
		end
		if done then
			done()
		end
	end

	M.run(opts)
	return name
end

--- A highlight that follows `progress`, which goes from 0 to 1. Unlike
--- `highlight` it can go back and forth, such as with the state of a row.
---@param from table
---@param to table
---@param progress fun(): number
---@param opts? { base?: table }
---@return string name
function M.tint(from, to, progress, opts)
	local name = acquire_group()
	local at = blended(from, to, opts and opts.base)

	reactive.effect(function()
		set_highlight(name, at(progress()))
	end)
	return name
end

--- Text that fades in from a background, as a highlight.
---@param group string highlight to end up as
---@param background? integer color to start from
---@param opts? markup.animate.opts
---@return string name
function M.fade_in(group, background, opts)
	local target = vim.api.nvim_get_hl(0, { name = group, link = false })
	local base = background or M.color("Normal", "bg") or 0

	if not target.fg or not M.enabled then
		return group
	end

	return M.highlight(
		{ fg = base },
		{ fg = target.fg },
		vim.tbl_extend("force", opts or {}, { base = target, link = group })
	)
end

return M
