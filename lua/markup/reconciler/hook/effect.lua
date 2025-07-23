local function mount_effect(fiber, create, deps)
	local hook = Markup.reconciler.mount_wip_hook()
	hook.memoized_state = {}
end

local function update_effect()
	local hook = Markup.reconciler.update_wip_hook()

	if hook then
		local prev_effect = hook.memoized_state
	end
	--
end

---@generic T
---@alias markup.effect
---| fun(initial_state: T): T, fun(value: T | fun(value: T): T?)

---@type markup.effect
local function effect(create, deps)
	local fiber = Markup.reconciler.current_fiber
	assert(fiber, "effect hook must be called within a fiber context")

	if not fiber.alternate then
		return mount_effect(fiber, create, deps)
	else
		return update_effect(fiber, create, deps)
	end
end

return effect
