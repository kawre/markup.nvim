local markup = require("markup.core")
local FiberTag = require("markup.core.fiber.enum").Tag

---@alias markup.create_fragment
---| fun(props: markup.create_element.props): markup.Element.Table

---@type markup.create_fragment
local function create_fragment(...)
	return markup.create_element(FiberTag.FRAGMENT, ...)
end

return create_fragment
