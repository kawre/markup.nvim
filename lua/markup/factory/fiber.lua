local Tag = require("markup.reconciler.enum").Tag
local Flag = require("markup.reconciler.enum").Flag
local Fiber = require("markup.reconciler.fiber")
local _type = type

---@class markup.factory.fiber
local M = Markup.singleton()

---@param tag markup.Fiber.tag
---@param props? table
---@param key? any
function M.call(tag, props, key)
	return Fiber(tag, props, key)
end

function M.from_text(content)
	return M.call(Tag.TEXT, content)
end

---@param element markup.element
function M.from_element(element)
	return M.from_type_and_props(element.type, element.props, element.key)
end

function M.from_type_and_props(type, props, key)
	local resolved_type = type

	local tag = Tag.ELEMENT

	if type == Tag.FRAGMENT then
		tag = Tag.FRAGMENT
	elseif _type(type) == "function" then
		tag = Tag.FUNCTION
	elseif _type(type) == "table" then
		---@type markup.element.typeof
		local typeof = type.typeof

		if not typeof then
			tag = Tag.FRAGMENT
		elseif typeof == "class" then
			tag = Tag.CLASS
		elseif typeof == "context" then
			tag = Tag.CONTEXT
		end
	end

	local fiber = M.call(tag, props, key)
	fiber.element_type = type
	fiber.type = resolved_type
	return fiber
end

---@param dom markup.dom
---@param element markup.element
function M.root(dom, element)
	local fiber = M.call(Tag.ROOT)
	fiber.pending_props = { children = element }
	fiber.state_node = Markup.factory.node(dom, "element", "root")
	fiber:set_flags(Flag.PLACEMENT)
	return fiber
end

return M
