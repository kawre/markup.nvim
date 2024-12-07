local markup = require("markup.core")

---@param element markup.ElementObject
local function create_fiber_from_element(element)
	return markup.create_fiber(element.type, element.props, element.key)
end

return create_fiber_from_element
