local Flag = require("markup.reconciler.enum").Flag

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
---@field deps table
---@field key? any
---@field hook? markup.Fiber.hook
---@field alternate? markup.fiber
---@field child? markup.fiber
---@field sibling? markup.fiber
---@field index integer
---@field deletions? markup.fiber[]
---@field hostf markup.fiber
local M = Markup.object()

---@param tag markup.Fiber.tag
---@param props? table
---@param key? any
function M:new(tag, props, key)
	self.pending_props = props
	self.key = key
	self.tag = tag
	self.flags = Flag.NONE
	self.index = 1
	self.__id = Markup.util.gen_id()
end

---@param ... markup.fiber.flag
function M:set_flags(...)
	self.flags = bit.bor(self.flags, ...)
end

---@param ... markup.fiber.flag
function M:clear_flags(...)
	self.flags = bit.band(self.flags, bit.bnot(bit.bor(...)))
end

---@param ... markup.fiber.flag
function M:check_flags(...)
	return self.flags == ... or bit.band(self.flags, ...) ~= 0
end

function M:reset_flags()
	self.flags = Flag.NONE
end

return M
