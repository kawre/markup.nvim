---@alias markup.ref
---| fun(): markup.node

local function ref()
	local fiber = Markup.reconciler.current_fiber
	assert(fiber, "`ref` hook must be called within a fiber context")

	return fiber.state_node
end

return ref
