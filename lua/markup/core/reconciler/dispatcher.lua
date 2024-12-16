local markup = require("markup.core")

local log = require("markup.logger") ---@diagnostic disable-line: unused-local
local FiberFlag = require("markup.core.reconciler.enum").Flag

---@class markup.Dispatcher
---@field reconciler markup.Reconciler
---@field queues table
local Dispatcher = setmetatable({}, {
	__call = function(self, reconciler)
		local instance = setmetatable({}, { __index = self })
		instance.queues = markup.Array()
		instance.reconciler = reconciler
		return instance
	end,
})

---@param fiber markup.Fiber
function Dispatcher:execute(fiber, fn, ...)
	FiberFlag.set(fiber, FiberFlag.UPDATE)
end

---@param fiber markup.Fiber
function Dispatcher:is_render_phase_update(fiber)
	local alternate = fiber.alternate
	local current_fiber = self.reconciler.currently_rendering_fiber
	return fiber == current_fiber or (alternate and alternate == current_fiber)
end

function Dispatcher:enqueue_update(update)
	self.queues:push(update)
end

---@param fiber markup.Fiber
---@param queue markup.Fiber.queue
---@param update markup.Fiber.update
function Dispatcher:enqueue_hook_update(fiber, queue, update)
	if not queue.pending then
		queue.pending = {}
	end

	table.insert(queue.pending, update)
	FiberFlag.set(fiber, FiberFlag.UPDATE)
end

---@param fiber markup.Fiber
---@param action function
function Dispatcher:set_state(fiber, action)
	-- if self:is_render_phase_update(fiber) then
	-- else
	-- self:enqueue_hook_update(fiber, queue, update)
	action()
	FiberFlag.set(fiber, FiberFlag.UPDATE)
	self.reconciler:schedule_render()
	-- end
end

function Dispatcher:dispatch() end

return Dispatcher
