---@class markup.dispatcher: markup.object
---@field reconciler markup.reconciler
---@field queues table
local M = Markup.singleton()

---@param hook markup.fiber.hook
---@param action function
function M.enqueue_hook_update(hook, action)
	local queue = hook.queue
	local update = {
		action = action,
	}

	if not queue.pending then
		queue.pending = { update }
	else
		table.insert(queue.pending, update)
	end
end

---@param fiber markup.fiber
function M.resolve_hook_updates(fiber)
	local hook = fiber.memoized_state

	while hook do
		if hook.queue.pending then
			for _, update in ipairs(hook.queue.pending) do
				M.execute(update.action)
			end
			hook.queue.pending = nil
		end
		hook = hook.next
	end
end

---@param hook markup.fiber.hook
---@param action function
function M.set_state(hook, action)
	M.enqueue_hook_update(hook, action)
end

function M.execute(fn, ...)
	Markup.log(fn)
	fn(...)
end

return M
