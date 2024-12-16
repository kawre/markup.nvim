local markup = require("markup.core")

local u = require("markup.utils")
local log = require("markup.logger") ---@diagnostic disable-line: unused-local

---@param initial any
local function mount_state(initial)
	local fiber, reconciler = markup.Reconciler.static.get_currently_rendering_fiber(true)

	initial = u.call_if_callable(initial)

	local hook = reconciler:mount_wip_hook({
		base_state = initial,
		memoized_state = initial,
	})

	hook.dispatch = function(value)
		reconciler.dispatcher:set_state(fiber, function()
			hook.memoized_state = u.call_if_callable(value, hook.memoized_state)
		end)
	end

	return hook.memoized_state, hook.dispatch
end

local function update_state()
	local reconciler = markup.Reconciler.static.get(true)

	local hook = reconciler:update_wip_hook()
	assert(hook, "`update_state` must be called while reconciler work, this is a bug.")
	return hook.memoized_state, hook.dispatch
end

---@generic T
---@alias markup.use_state
---| fun(initial_state: T): T, fun(value: T | fun(value: T): T?)

---@type markup.use_state
local function use_state(initial)
	local fiber = markup.Reconciler.static.get_currently_rendering_fiber(true)

	-- log.info(fiber.memoized_state)
	if not fiber.memoized_state then
		return mount_state(initial)
	else
		return update_state()
	end
end

return use_state
