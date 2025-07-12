local FiberTag = require("markup.core.reconciler.enum").Tag
local NodeFactory = require("markup.core.factory.node")

---@param etype markup.Fiber.type
local function tag_from_type(etype)
	if type(etype) == "function" then
		return FiberTag.FUNCTION
	elseif type(etype) == "table" and type(etype.render) == "function" then
		return FiberTag.CLASS
	elseif type(etype) == "string" then
		return FiberTag.ELEMENT
	else
		error("Unknown element type " .. vim.inspect(etype))
	end
end

---@class markup.factory.Fiber
local M = {}

---@type markup.create_fiber
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
	local fiber = M.create_from_type_and_props(element.type, element.props, element.key)
	fiber._style = element._style
	return fiber
end

function M.create_from_type_and_props(_type, props, key)
	local resolved_type = _type
	local tag

	if type(_type) == "string" then
		tag = FiberTag.ELEMENT
		resolved_type = _type
	elseif type(_type) == "function" then
		tag = FiberTag.FUNCTION
		resolved_type = _type
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
