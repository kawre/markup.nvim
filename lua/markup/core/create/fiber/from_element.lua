local markup = require("markup.core")

---@alias markup.create_fiber_from_element
---| fun(element: markup.xElement): markup.Fiber

---@type markup.create_fiber_from_element
local function create_fiber_from_element(element)
	local fiber = markup.create_fiber(element.type, element.props, element.key)
	-- fiber.memoized_state = { element = element }
	return fiber
end

return create_fiber_from_element
