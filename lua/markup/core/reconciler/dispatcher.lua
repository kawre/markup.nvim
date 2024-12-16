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
---@param action function
function Dispatcher:set_state(fiber, action)
	action()
	FiberFlag.set(fiber, FiberFlag.UPDATE)
	self.reconciler:schedule_render()
end

return Dispatcher
