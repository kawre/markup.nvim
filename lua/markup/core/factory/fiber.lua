local Tag = require("markup.core.reconciler.enum").Tag
local Flag = require("markup.core.reconciler.enum").Flag
local NodeFactory = require("markup.core.factory.node")
local Fiber = require("markup.core.reconciler.fiber.init")
local typeof = type

---@class markup.factory.Fiber
local M = {}

---@param tag markup.Fiber.tag
---@param props? table
---@param key? any
function M.create(tag, props, key)
	return Fiber:new(tag, props, key)
end

function M.create_from_text(content)
	return M.create(Tag.TEXT, content)
end

---@param element markup.Element
function M.create_from_element(element)
	return M.create_from_type_and_props(element.type, element.props, element.key)
end

function M.create_from_type_and_props(type, props, key)
	local resolved_type = type

	-- default to element type
	local tag = Tag.ELEMENT

	if type == Tag.FRAGMENT then
		tag = Tag.FRAGMENT
	elseif typeof(type) == "function" then
		tag = Tag.FUNCTION
	elseif typeof(type) == "table" and not getmetatable(type) then
		tag = Tag.FRAGMENT
	end

	local fiber = M.create(tag, props, key)
	fiber.element_type = type
	fiber.type = resolved_type
	return fiber
end

---@param element markup.Element
function M.create_root(element)
	local fiber = M.create(Tag.ROOT)
	fiber.pending_props = { children = element }
	fiber.state_node = NodeFactory.create("element", "root")
	fiber.flags:set(Flag.PLACEMENT)
	return fiber
end

return M
