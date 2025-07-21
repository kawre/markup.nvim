local FiberFlags = require("markup.reconciler.fiber.flags")

---@class markup.Fiber.queue
---@field dispatch function
---@field pending? { action: fun() }[]
---@field last_rendered_state any

---@class markup.Fiber.hook
---@field memoized_state any
---@field base_state any
---@field queue markup.Fiber.queue
---@field next? markup.Fiber.hook

---@class markup.fiber
---@field pending_props any
---@field memoized_props any
---@field memoized_state any
---@field type markup.Fiber.type
---@field element_type string
---@field tag markup.Fiber.tag
---@field return? markup.fiber
---@field state_node markup.node
---@field key? any
---@field hook? markup.Fiber.hook
---@field alternate? markup.fiber
---@field child? markup.fiber
---@field sibling? markup.fiber
---@field index integer
---@field deletions? markup.fiber[]
---@field hostf markup.fiber
local M = {}

---@param tag markup.Fiber.tag
---@param props? table
---@param key? any
function M.new(tag, props, key)
	local self = setmetatable({}, M)

	self.pending_props = props
	self.key = key
	self.tag = tag
	self.flags = FiberFlags:new()
	self.index = 1
	self.__id = Markup.util.gen_id()

	return self
end

return M
