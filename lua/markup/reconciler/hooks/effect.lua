local M = Markup.singleton()

---@alias markup.hooks.effect
---| fun(create: function, deps?: table)

---@type markup.hooks.effect
function M.call(create, deps)
	local fiber = Markup.reconciler.current_fiber
	assert(fiber, "effect hook must be called within a fiber context")
	assert(type(create) == "function", "effect hook must be a function")

	if not fiber.alternate then
		return M.mount_effect(fiber, create, deps)
	else
		return M.update_effect(fiber, create, deps)
	end
end

---@param fiber markup.fiber
---@param create function
---@param deps table
function M.mount_effect(fiber, create, deps)
	local hook = Markup.reconciler.mount_wip_hook()
	hook.memoized_state = Markup.dispatcher.push_effect(fiber, create, { destroy = nil }, deps)
end

---@param fiber markup.fiber
---@param create function
---@param deps table
function M.update_effect(fiber, create, deps)
	local hook = Markup.reconciler.update_wip_hook()
	local inst = hook.memoized_state.inst
	Markup.assert.user_hook(inst)
	local current_hook = Markup.reconciler.current_hook

	if current_hook and deps then
		local prev_effect = current_hook.memoized_state ---@cast prev_effect markup.fiber.hook.effect
		local prev_deps = prev_effect.deps

		if not Markup.util.shallow_eq(prev_deps, deps) then
			Markup.dispatcher.push_effect(fiber, create, inst, deps)
		end
	end
end

return M
