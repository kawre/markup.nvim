local normalizer = require("markup.core.node.normalizer")
local FiberTag = require("markup.core.reconciler.enum").Tag

---@class markup.factory.Node
local M = {}

---@param type markup.Node.type
---@param name? string
---@param props? markup.Node.props
function M.create(type, name, props)
	local Node = require("markup.core.node")
	return Node:new(type, name, props)
end

---@param element markup.Element
function M.create_from_element(element)
	local props = normalizer.props(element.props, element._style)
	local node = M.create("element", element.type, props)
	return node
end

---@param content string|number
function M.create_from_text(content)
	local node = M.create("text")
	node:set_text_content(content)
	return node
end

---@param fiber markup.Fiber
function M.create_from_fiber(fiber)
	local node
	if fiber.tag == FiberTag.TEXT then
		local props = fiber.pending_props
		local text_content = type(props) == "table" and props.children or props
		node = M.create_from_text(text_content)
	elseif fiber.tag == FiberTag.ELEMENT then
		node = M.create("element", fiber.element_type, fiber.pending_props)
	else
		error("Unknown fiber tag: " .. vim.inspect(fiber.tag))
	end

	node.fiber = fiber
	return node
end

return M
