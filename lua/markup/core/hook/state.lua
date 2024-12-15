local markup = require("markup.core")

local u = require("markup.utils")
local Hooks = require("markup.core.hook")

local log = require("markup.logger") ---@diagnostic disable-line: unused-local
local FiberFlag = require("markup.core.reconciler.enum").Flag

---@generic T
---@alias markup.use_state
---| fun(initial_state: T): T, fun(value: T | fun(value: T): T?)

---@type markup.use_state
local function use_state(initial)
	local reconciler = markup.Reconciler.static.get()
	assert(reconciler, "`use_state` must be called while reconciler work, this is a bug.")
	local fiber = reconciler.currently_rendering_fiber
	assert(fiber, "`use_state` must be called inside a fiber, this is a bug.")

	initial = u.call_if_callable(initial)

	local hook = reconciler:mount_wip_hook()
	hook.base_state = initial
	hook.memoized_state = hook.base_state

	hook.queue = {
		pending = nil,
		last_rendered_state = initial,
	}

	local function dispatch(value)
		reconciler.dispatcher:set_state(fiber, hook.queue, function()
			hook.memoized_state = u.call_if_callable(value, hook.memoized_state)
		end)
	end
	-- hook.queue.dispatch = dispatch

	return hook.memoized_state, dispatch
end

return use_state
