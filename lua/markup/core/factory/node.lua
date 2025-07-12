local normalizer = require("markup.core.node.normalizer")
local Node = require("markup.core.node.init2")
local FiberTag = require("markup.core.reconciler.enum").Tag

---@class markup.factory.Node
local M = {}

---@param type markup.Node.type
---@param name? string
---@param props? markup.Node.constructor.props
function M.create(type, name, props)
	return Node:new(type, name, props)
end

---@param element markup.Element
function M.create_from_element(element)
	local props = normalizer.props(element.props, element._style)
	local node = M.create("element", element.type, props)
	return node
end

---@param fiber markup.Fiber
function M.create_from_fiber(fiber)
	if fiber.tag == FiberTag.TEXT then
		return M.create("text", fiber.element_type, fiber.pending_props)
	elseif fiber.tag == FiberTag.ELEMENT then
		return M.create("element", fiber.element_type, fiber.pending_props)
	else
		error("Unknown fiber tag: " .. vim.inspect(fiber.tag))
	end
end

return M
