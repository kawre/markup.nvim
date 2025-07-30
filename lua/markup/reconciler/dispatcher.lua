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

return M
