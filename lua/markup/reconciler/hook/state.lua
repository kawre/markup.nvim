---@param initial any
local function mount_state(initial)
	local reconciler = Markup.reconciler.static.get(true)

	initial = Markup.util.call_if_callable(initial)

	local hook = reconciler:mount_wip_hook({
		base_state = initial,
		memoized_state = initial,
		queue = {
			last_rendered_state = initial,
			pending = nil,
		},
	})

	hook.queue.dispatch = function(value)
		reconciler.dispatcher:set_state(hook, function()
			hook.memoized_state = Markup.util.call_if_callable(value, hook.memoized_state)
		end)
	end

	return hook.memoized_state, hook.queue.dispatch
end

local function update_state()
	local reconciler = Markup.reconciler.static.get(true)

	local hook = reconciler:update_wip_hook()
	assert(hook, "`update_state` must be called while reconciler work, this is a bug.")
	return hook.memoized_state, hook.queue.dispatch
end

---@generic T
---@alias markup.use_state
---| fun(initial_state: T): T, fun(value: T | fun(value: T): T?)

---@type markup.use_state
local function use_state(initial)
	local fiber = Markup.reconciler.static.get_currently_rendering_fiber(true)

	if not fiber.memoized_state then
		return mount_state(initial)
	else
		return update_state()
	end
end

return use_state
