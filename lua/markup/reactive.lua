--- Fine grained reactivity.
---
--- A signal remembers which computations read it. Writing queues those
--- computations, and they all run together in one scheduled flush, so any
--- number of writes in a tick costs a single update.
---
--- Every computation belongs to an owner. Disposing an owner stops everything
--- created under it, which is how unmounted UI releases its subscriptions.

---@class markup.reactive
local M = {}

---@class markup.reactive.owner
---@field parent? markup.reactive.owner
---@field children? table<markup.reactive.owner, boolean>
---@field cleanups? function[]
---@field context? table
---@field disposed? boolean

---@class markup.reactive.computation: markup.reactive.owner
---@field fn function
---@field deps table<table, boolean>
---@field memo? boolean
---@field stale? boolean
---@field subs? table<markup.reactive.computation, boolean>
---@field value? any

local MAX_ROUNDS = 100

local owner ---@type markup.reactive.owner?
local observer ---@type markup.reactive.computation?

local counts = { effects = 0, memos = 0, scopes = 0, signals = 0, runs = 0, flushes = 0 }

local queue, queue_len = {}, 0
local queued = {} ---@type table<markup.reactive.computation, boolean>
local jobs, job_order = {}, {}
local scheduled = false

local function report(err)
	vim.schedule(function()
		vim.notify(("markup: %s"):format(err), vim.log.levels.ERROR)
	end)
end

local flush

local function schedule()
	if not scheduled then
		scheduled = true
		vim.schedule(flush)
	end
end

--- Which live counter an owner belongs to.
local function kind_of(target)
	if target.memo then
		return "memos"
	end
	return target.fn and "effects" or "scopes"
end

local function adopt(child, parent)
	local kind = kind_of(child)
	counts[kind] = counts[kind] + 1
	child.parent = parent
	if parent then
		parent.children = parent.children or {}
		parent.children[child] = true
	end
	return child
end

local function clear_deps(computation)
	for dep in pairs(computation.deps) do
		dep.subs[computation] = nil
	end
	computation.deps = {}
end

--- Runs cleanups and disposes children, keeping the owner itself usable.
local function reset(target)
	local children = target.children
	if children then
		target.children = nil
		for child in pairs(children) do
			M.dispose(child)
		end
	end

	local cleanups = target.cleanups
	if cleanups then
		target.cleanups = nil
		for i = #cleanups, 1, -1 do
			local ok, err = pcall(cleanups[i])
			if not ok then
				report(err)
			end
		end
	end
end

---@param target markup.reactive.owner
function M.dispose(target)
	if target.disposed then
		return
	end
	target.disposed = true
	local kind = kind_of(target)
	counts[kind] = counts[kind] - 1
	if target.parent and target.parent.children then
		target.parent.children[target] = nil
	end
	reset(target)
	if target.deps then
		clear_deps(target)
	end
end

local function track(source)
	if observer then
		observer.deps[source] = true
		source.subs[observer] = true
	end
end

--- Effects are queued, memos only go stale until someone reads them, so a
--- computation never sees a mix of old and new values.
local function notify(source)
	for sub in pairs(source.subs) do
		if sub.memo then
			if not sub.stale then
				sub.stale = true
				notify(sub)
			end
		elseif not queued[sub] then
			queued[sub] = true
			queue_len = queue_len + 1
			queue[queue_len] = sub
		end
	end
	if queue_len > 0 then
		schedule()
	end
end

local function run(computation)
	counts.runs = counts.runs + 1
	reset(computation)
	clear_deps(computation)

	local prev_owner, prev_observer = owner, observer
	owner, observer = computation, computation
	local ok, err = xpcall(computation.fn, debug.traceback)
	owner, observer = prev_owner, prev_observer

	if not ok then
		report(err)
	end
end

---@generic T
---@param initial T
---@return fun(value?: T|fun(previous: T): T): T
function M.signal(initial)
	local source = { value = initial, subs = {} }
	counts.signals = counts.signals + 1

	return function(...)
		if select("#", ...) == 0 then
			track(source)
			return source.value
		end

		local value = ...
		if type(value) == "function" then
			value = value(source.value)
		end
		if value ~= source.value then
			source.value = value
			notify(source)
		end
		return value
	end
end

--- A cached value derived from signals, computed when first read.
---@generic T
---@param fn fun(): T
---@return fun(): T
function M.memo(fn)
	local computation = adopt({ fn = fn, deps = {}, subs = {}, memo = true, stale = true }, owner)

	return function()
		if computation.stale then
			computation.stale = false
			reset(computation)
			clear_deps(computation)

			local prev_owner, prev_observer = owner, observer
			owner, observer = computation, computation
			local ok, value = xpcall(fn, debug.traceback)
			owner, observer = prev_owner, prev_observer

			if not ok then
				computation.stale = true
				error(value, 0)
			end
			computation.value = value
		end

		track(computation)
		return computation.value
	end
end

--- Runs `fn` now, and again after anything it read changes.
---@param fn function
---@return markup.reactive.computation
function M.effect(fn)
	local computation = adopt({ fn = fn, deps = {} }, owner)
	run(computation)
	return computation
end

--- The owner of the code running now.
---@return markup.reactive.owner?
function M.current_owner()
	return owner
end

--- Runs `fn` in a new owner that lives until it is disposed.
---
--- Pass `parent` when the scope must outlive the computation creating it. An
--- effect disposes what it owns before each rerun, so `show` and `each` hang
--- their contents off the owner around their effect.
---@generic T
---@param fn fun(owner: markup.reactive.owner): T
---@param parent? markup.reactive.owner
---@return T, markup.reactive.owner
function M.scope(fn, parent)
	local created = adopt({}, parent or owner)
	local prev_owner, prev_observer = owner, observer
	owner, observer = created, nil
	local results = { xpcall(fn, debug.traceback, created) }
	owner, observer = prev_owner, prev_observer

	if not results[1] then
		M.dispose(created)
		error(results[2], 0)
	end
	return results[2], created
end

--- Runs `fn` without subscribing to what it reads.
---@generic T
---@param fn fun(): T
---@return T
function M.untrack(fn)
	local previous = observer
	observer = nil
	local results = { xpcall(fn, debug.traceback) }
	observer = previous

	if not results[1] then
		error(results[2], 0)
	end
	return results[2]
end

--- Registers `fn` to run when the current owner is disposed or rerun.
---@param fn function
function M.on_cleanup(fn)
	if owner then
		owner.cleanups = owner.cleanups or {}
		owner.cleanups[#owner.cleanups + 1] = fn
	end
end

--- Sets a value visible to everything created under the current owner.
function M.provide(key, value)
	assert(owner, "`provide` must be called inside a component")
	owner.context = owner.context or {}
	owner.context[key] = value
end

--- Reads the nearest value set with `provide`.
function M.inject(key, fallback)
	local current = owner
	while current do
		local context = current.context
		if context and context[key] ~= nil then
			return context[key]
		end
		current = current.parent
	end
	return fallback
end

--- Queues `job` to run once after the next flush's effects.
---@param job function
function M.after_flush(job)
	if not jobs[job] then
		jobs[job] = true
		job_order[#job_order + 1] = job
	end
	schedule()
end

--- Runs everything pending now instead of waiting for the scheduled flush.
function M.flush()
	flush()
end

--- Live effects, memos and scopes, plus totals since startup. Signals have no
--- owner, so `signals` counts every one ever created.
---@return { effects: integer, memos: integer, scopes: integer, signals: integer, runs: integer, flushes: integer }
function M.stats()
	return vim.deepcopy(counts)
end

flush = function()
	scheduled = false
	counts.flushes = counts.flushes + 1

	local rounds = 0
	while queue_len > 0 do
		rounds = rounds + 1
		if rounds > MAX_ROUNDS then
			for i = 1, queue_len do
				queued[queue[i]] = nil
			end
			queue, queue_len = {}, 0
			report("effects kept writing signals they depend on, giving up")
			break
		end

		local batch, len = queue, queue_len
		queue, queue_len = {}, 0
		for i = 1, len do
			local computation = batch[i]
			queued[computation] = nil
			if not computation.disposed then
				run(computation)
			end
		end
	end

	if #job_order > 0 then
		local pending = job_order
		jobs, job_order = {}, {}
		for _, job in ipairs(pending) do
			local ok, err = xpcall(job, debug.traceback)
			if not ok then
				report(err)
			end
		end
	end
end

return M
