local markup = require("markup.core")

local log = require("markup.logger") ---@diagnostic disable-line: unused-local

---@class markup.Dispatcher
---@field reconciler markup.Reconciler
---@field queues table
local Dispatcher = setmetatable({}, {
	__call = function(self, reconciler)
		local instance = setmetatable({}, { __index = self })
		instance.reconciler = reconciler
		return instance
	end,
})

---@param hook markup.Fiber.hook
---@param action function
function Dispatcher:enqueue_hook_update(hook, action)
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

---@param fiber markup.Fiber
function Dispatcher:resolve_hook_updates(fiber)
	local hook = fiber.memoized_state

	while hook do
		if hook.queue.pending then
			for _, update in ipairs(hook.queue.pending) do
				self:execute(update.action)
			end
			hook.queue.pending = nil
		end
		hook = hook.next
	end
end

---@param hook markup.Fiber.hook
---@param action function
function Dispatcher:set_state(hook, action)
	self:enqueue_hook_update(hook, action)
	self.reconciler:schedule_render()
end

function Dispatcher:execute(fn, ...)
	fn(...)
end

return Dispatcher
