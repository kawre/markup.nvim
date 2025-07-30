local Tag = require("markup.reconciler.enum").Tag
local Flag = require("markup.reconciler.enum").Flag

---@class markup.dispatcher
---@field reconciler markup.reconciler
---@field queues table
local M = Markup.singleton()

function M.enqueue_hook_update(queue, update)
	local pending = queue.pending

	if not pending then
		-- This is the first update. Create a circular list.
		update.next = update
	else
		update.next = pending.next
		pending.next = update
	end

	queue.pending = update
end

---@param fiber markup.fiber
function M.resolve_hook_updates(fiber)
	local hook = fiber.memoized_state

	while hook do
		if hook.queue and hook.queue.pending then
			local first_update = hook.queue.pending.next
			local update = first_update

			repeat
				update.action()
				update = update.next
			until update == first_update
			hook.queue.pending = nil
		end
		hook = hook.next
	end
end

---@param fiber markup.fiber
---@param create function
---@param inst { destroy?: function }
---@param deps table
function M.push_effect(fiber, create, inst, deps)
	local effect = {
		typeof = "effect",
		deps = deps,
		create = create,
		inst = inst,
		next = nil,
	}

	fiber.update_queue = fiber.update_queue or {}

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

	return effect
end

---@param fiber markup.fiber
---@param create function
---@param deps table
function M.mount_effect(fiber, create, deps)
	local hook = Markup.reconciler.mount_wip_hook()
	hook.memoized_state = M.push_effect(fiber, create, { destroy = nil }, deps)
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
			M.push_effect(fiber, create, inst, deps)
		end
	end
end

---@alias markup.hooks.effect
---| fun(create: function, deps?: table)

---@type markup.hooks.effect
function M.effect(create, deps)
	local fiber = Markup.reconciler.current_fiber
	assert(fiber, "effect hook must be called within a fiber context")
	assert(type(create) == "function", "effect hook must be a function")

	if not fiber.alternate then
		return M.mount_effect(fiber, create, deps)
	else
		return M.update_effect(fiber, create, deps)
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

		M.enqueue_hook_update(hook.queue, update)
		current_renderer:schedule_rerender()
	end

	return hook.memoized_state, hook.queue.dispatch
end

function M.update_variable()
	local hook = Markup.reconciler.update_wip_hook()
	Markup.assert.user_hook(hook.queue)
	return hook.memoized_state, hook.queue.dispatch
end

---@generic T
---@alias markup.hooks.variable
---| fun(initial_state: T): T, fun(value: T | fun(value: T): T?)

---@type markup.hooks.variable
function M.variable(initial)
	local fiber = Markup.reconciler.current_fiber
	assert(fiber, "use_state hook must be called within a fiber context")

	if not fiber.alternate then
		return M.mount_variable(initial)
	else
		return M.update_variable()
	end
end

---@alias markup.hooks.use function

function M.use(spec)
	if spec.typeof == Tag.CONTEXT then
		---@cast spec markup.hooks.context
		return spec:read()
	end
end

---@alias markup.hooks.window
---| fun(): markup.window

function M.window()
	local renderer = Markup.renderer.current
	assert(renderer, "`view` hook must be called within a renderer context")
	return renderer.win
end

---@class markup.hooks.context.dep
---@field ctx markup.hooks.context
---@field memoized_value any
---@field next markup.hooks.context.dep?

---@class markup.hooks.context
---@field current any
---@field typeof string
---@overload fun(default): markup.hooks.context
M.context = Markup.object()

---@param default any
function M.context:new(default)
	self.typeof = Tag.CONTEXT
	self.current = default
end

function M.context:provider(...)
	return Markup.factory.element(self, ...)
end

function M.context:read_for_consumer(consumer)
	local value = self.current

	---@type markup.hooks.context.dep
	local ctx_dep = { ctx = self, memoized_value = value, next = nil }

	if not Markup.reconciler.last_context_dep then
		Markup.reconciler.last_context_dep = ctx_dep
		consumer.deps = { first_context = ctx_dep }
	else
		Markup.reconciler.last_context_dep.next = ctx_dep
		Markup.reconciler.last_context_dep = ctx_dep
	end

	return value
end

function M.context:read()
	local fiber = Markup.reconciler.current_fiber
	assert(fiber, "Cannot read context outside of a fiber")
	return self:read_for_consumer(fiber)
end

---@class markup.hooks
M.hooks = {
	effect = M.effect,
	variable = M.variable,
	use = M.use,
	window = M.window,
	context = M.context,
}

return M
