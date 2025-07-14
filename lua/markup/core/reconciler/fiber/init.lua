local FiberFlags = require("markup.core.reconciler.fiber.flags")

---@class markup.Fiber.queue
---@field dispatch function
---@field pending? { action: fun() }[]
---@field last_rendered_state any

---@class markup.Fiber.hook
---@field memoized_state any
---@field base_state any
---@field queue markup.Fiber.queue
---@field next? markup.Fiber.hook

---@class markup.Fiber
---@field pending_props any
---@field memoized_props any
---@field memoized_state any
---@field type markup.Fiber.type
---@field element_type string
---@field tag markup.Fiber.tag
---@field state_node markup.Node
---@field key? any
---@field hook? markup.Fiber.hook
---@field alternate? markup.Fiber
---@field child? markup.Fiber
---@field sibling? markup.Fiber
---@field index integer
---@field deletions? markup.Fiber[]
local Fiber = {}

---@param tag markup.Fiber.tag
---@param props? table
---@param key? any
function Fiber:new(tag, props, key)
	self = setmetatable({}, Fiber)

	self.pending_props = props
	self.key = key
	self.tag = tag
	self.flags = FiberFlags:new()
	self.index = 1

	return self
end

return Fiber
