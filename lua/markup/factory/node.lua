-- local normalizer = require("markup.node.normalizer")
local FiberTag = require("markup.reconciler.enum").Tag
local Node = require("markup.node")

---@class markup.factory.node
local M = Markup.singleton()

---@param dom markup.dom
---@param type markup.node.type
---@param name? string
---@param props? markup.node.props
function M.call(dom, type, name, props)
	if type == "element" then
		return dom:create_element(name, props)
	elseif type == "text" then
		return dom:create_text_node(name)
	else
		error("Unknown node type: " .. vim.inspect(type))
	end
end

---@param dom markup.dom
---@param element markup.element
function M.from_element(dom, element)
	return M.call(dom, "element", element.type, element.props)
end

---@param dom markup.dom
---@param content string|number
function M.from_text(dom, content)
	return M.call(dom, "text", content)
end

---@param dom markup.dom
---@param fiber markup.fiber
function M.from_fiber(dom, fiber)
	local node
	if fiber.tag == FiberTag.TEXT then
		local props = fiber.pending_props
		local text_content = type(props) == "table" and props.children or props
		node = M.from_text(dom, text_content)
	elseif fiber.tag == FiberTag.ELEMENT then
		node = M.call(dom, "element", fiber.element_type, fiber.pending_props)
	else
		error("Unknown fiber tag: " .. vim.inspect(fiber.tag))
	end

	-- node.fiber = fiber
	return node
end

return M
