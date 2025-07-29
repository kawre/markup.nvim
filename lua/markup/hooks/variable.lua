local Dispatcher = require("markup.reconciler.dispatcher")

---@param initial any
local function mount_state(initial)
	initial = Markup.util.call(initial)

	local hook = Markup.reconciler.mount_wip_hook({
		base_state = initial,
		memoized_state = initial,
		queue = {
			last_rendered_state = initial,
			pending = nil,
		},
	})

	local current_renderer = Markup.renderer.current
	assert(current_renderer, "`variable:set(...)` must be called within a renderer context")

	hook.queue.dispatch = function(value)
		Dispatcher.set_state(hook, function()
			if type(value) == "function" then
				value = value(hook.memoized_state)
			end
			-- hook.memoized_state = Markup.util.call(value, hook.memoized_state)
			hook.memoized_state = value
		end)
		current_renderer:schedule_rerender()
	end

	return hook.memoized_state, hook.queue.dispatch
end

local function update_state()
	local hook = Markup.reconciler.update_wip_hook()
	assert(hook, "`update_state` must be called while reconciler work, this is a bug.")
	return hook.memoized_state, hook.queue.dispatch
end

---@generic T
---@alias markup.use_state
---| fun(initial_state: T): T, fun(value: T | fun(value: T): T?)

---@type markup.use_state
local function use_state(initial)
	local fiber = Markup.reconciler.current_fiber
	assert(fiber, "use_state hook must be called within a fiber context")

	if not fiber.memoized_state then
		return mount_state(initial)
	else
		return update_state()
	end
end

return use_state
