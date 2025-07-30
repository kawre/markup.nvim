local M = Markup.singleton()

---@generic T
---@alias markup.hooks.variable
---| fun(initial_state: T): T, fun(value: T | fun(value: T): T?)

function M.call(initial)
	local fiber = Markup.reconciler.current_fiber
	assert(fiber, "use_state hook must be called within a fiber context")

	if not fiber.alternate then
		return M.mount_variable(initial)
	else
		return M.update_variable()
	end
end

---@param initial any
function M.mount_variable(initial)
	local current_renderer = Markup.renderer.current
	Markup.assert.user(current_renderer, "`set variable` must be called within a renderer context") ---@cast current_renderer -nil

	initial = Markup.util.call(initial)
	local hook = Markup.reconciler.mount_wip_hook({
		base_state = initial,
		memoized_state = initial,
		queue = {
			last_rendered_state = initial,
			pending = nil,
			dispatch = nil,
		},
	})

	hook.queue.dispatch = function(value)
		local update = {
			action = function()
				if type(value) == "function" then
					value = value(hook.memoized_state)
				end
				if hook.memoized_state ~= value then
					hook.memoized_state = value
					hook.queue.last_rendered_state = value
				end
			end,
			next = nil,
		}

		Markup.dispatcher.enqueue_hook_update(hook.queue, update)
		current_renderer:schedule_rerender()
	end

	return hook.memoized_state, hook.queue.dispatch
end

function M.update_variable()
	local hook = Markup.reconciler.update_wip_hook()
	Markup.assert.user_hook(hook.queue)
	return hook.memoized_state, hook.queue.dispatch
end

return M
