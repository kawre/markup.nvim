local FiberTag = require("markup.core.reconciler.enum").Tag
local NodeFactory = require("markup.core.factory.node")

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
---@field flags integer
---@field key? any
---@field hook? markup.Fiber.hook
---@field alternate? markup.Fiber
---@field child? markup.Fiber
---@field sibling? markup.Fiber
---@field index integer
---@field deletions? markup.Fiber[]

---@class markup.factory.Fiber
local M = {}

---@param tag markup.Fiber.tag
function M.create(tag, props, key)
	return {
		pending_props = props,
		key = key,
		tag = tag,
		flags = 0,
		index = 1,
	}
end

function M.create_from_text(content)
	return M.create(FiberTag.TEXT, content)
end

---@param element markup.Element
function M.create_from_element(element)
	return M.create_from_type_and_props(element.type, element.props, element.key)
end

function M.create_from_type_and_props(_type, props, key)
	local resolved_type = _type

	local tag
	if _type == FiberTag.FRAGMENT then
		tag = FiberTag.FRAGMENT
	elseif type(_type) == "string" then
		tag = FiberTag.ELEMENT
	elseif type(_type) == "function" then
		tag = FiberTag.FUNCTION
	end

	local fiber = M.create(tag, props, key)
	fiber.element_type = _type
	fiber.type = resolved_type
	return fiber
end

---@param element markup.Element
function M.create_root(element)
	local fiber = M.create(FiberTag.ROOT)
	fiber.pending_props = { children = element }
	fiber.state_node = NodeFactory.create("element", "root")
	return fiber
end

return M
