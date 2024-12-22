local markup = require("markup.core")
local FiberTag = require("markup.core.reconciler.enum").Tag

---@alias markup.create_fiber_from_element
---| fun(element: markup.xElement): markup.Fiber

---@type markup.create_fiber_from_element
local function create_fiber_from_element(element)
	--
	-- if type(element.type) == "function" then
	-- 	fiber.children = element.children
	-- elseif type(element.type) == 'string' then
	-- elseif type(element.type)
	-- end
	--
	local fiber = markup.create_fiber(element.type, element.props, element.key)
	return fiber
end

return create_fiber_from_element
