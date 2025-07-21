local normalizer = require("markup.node.normalizer")
local FiberTag = require("markup.reconciler.enum").Tag
local Node = require("markup.node")

---@class markup.factory.node
local M = setmetatable({}, {
	__call = function(t, ...)
		return t.new(...)
	end,
})

---@param type markup.node.type
---@param name? string
---@param props? markup.node.props
function M.new(type, name, props)
	return Node(type, name, props)
end

---@param element markup.element
function M.from_element(element)
	local props = normalizer.props(element.props, element._style)
	local node = M.new("element", element.type, props)
	return node
end

---@param content string|number
function M.from_text(content)
	local node = M.new("text")
	node:set_text_content(content)
	return node
end

---@param fiber markup.fiber
function M.from_fiber(fiber)
	local node
	if fiber.tag == FiberTag.TEXT then
		local props = fiber.pending_props
		local text_content = type(props) == "table" and props.children or props
		node = M.from_text(text_content)
	elseif fiber.tag == FiberTag.ELEMENT then
		node = M.new("element", fiber.element_type, fiber.pending_props)
	else
		error("Unknown fiber tag: " .. vim.inspect(fiber.tag))
	end

	node.fiber = fiber
	return node
end

return M
