local markup = require("markup.core")

---@alias markup.create_fiber_from_text
---| fun(content: string|number): markup.Fiber

---@type markup.create_fiber_from_element
local function create_fiber_from_text(content)
	return markup.create_fiber(markup.Text, tostring(content))
end

return create_fiber_from_text
