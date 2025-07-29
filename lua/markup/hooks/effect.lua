local function push_effect(fiber, create, deps)
	local effect = {
		deps = deps,
		destroy = nil,
		next = nil,
	}

	fiber.update_queue = fiber.update_queue
		or {
			last_effect = nil,
			events = nil,
			stores = nil,
			memoCache = nil,
		}

	local last_effect = fiber.update_queue.last_effect
	if not last_effect then
		effect.next = effect
		fiber.update_queue.last_effect = effect
	else
		local first_effect = last_effect.next
		last_effect.next = effect
		effect.next = first_effect
		fiber.update_queue.last_effect = effect
	end

	effect.destroy = create()

	return effect
end

local function mount_effect(fiber, create, deps)
	local hook = Markup.reconciler.mount_wip_hook()
	hook.memoized_state = push_effect(fiber, create, deps)
end

local function update_effect(fiber, create, deps)
	local hook = Markup.reconciler.update_wip_hook()
	---@type markup.fiber.hook.effect
	local effect = hook.memoized_state

	local did_update = false
	if #effect.deps == #deps then
		for i, dep in ipairs(effect.deps) do
			if deps[i] ~= dep then
				did_update = true
				break
			end
		end
	end

	if did_update then
		Markup.util.call(effect.destroy)
		effect.destroy = create()
		effect.deps = deps
	end
end

---@generic T
---@alias markup.effect
---| fun(function, table)

---@type markup.effect
local function effect(create, deps)
	local fiber = Markup.reconciler.current_fiber
	assert(fiber, "effect hook must be called within a fiber context")
	assert(type(create) == "function", "effect hook must be a function")

	if not fiber.alternate then
		return mount_effect(fiber, create, deps or {})
	else
		return update_effect(fiber, create, deps or {})
	end
end

return effect
