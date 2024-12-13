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
	local fiber = reconciler.currently_rendering_fiber
	assert(fiber, "`use_state` must be called inside a fiber, this is a bug.")

	if u.is_callable(initial) then
		initial = initial()
	end

	local hook = reconciler:mount_wip_hook()
	hook.base_state = initial
	hook.memoized_state = hook.base_state

	local dispatch = function()
		reconciler.dispatcher:set_state(fiber, hook.queue)
	end

	local queue = {
		pending = nil,
		dispatch = dispatch,
		last_rendered_state = initial,
	}
	hook.queue = queue

	return hook.memoized_state, dispatch
end

return use_state
