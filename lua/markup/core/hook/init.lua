local markup = require("markup.core")

---@class markup.hook
local Hooks = {}

---@class markup.Fiber.hook
---@field memoized_state any
---@field base_state any
---@field base_queue any
---@field queue any
---@field next? markup.Fiber.hook

function Hooks.mount_wip_hook()
	---@type markup.Fiber.hook
	local hook = {
		memoized_state = nil,
		base_state = nil,
		next = nil,
	}

	if not markup.Reconciler.static.wip_hook then
		-- first hook to be mounted
		markup.Reconciler.static.wip_hook = hook
	else
		markup.Reconciler.static.wip_hook.next = hook
	end

	return markup.Reconciler.static.wip_hook
end

return Hooks
