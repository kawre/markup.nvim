local FiberTag = require("markup.core.reconciler.enum").Tag

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
		-- type = type,
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

function M.create_from_type_and_props(type, props, key)
	local resolved_type = type
	local tag = FiberTag.FUNCTION

	local fiber = M.create(tag, props, key)
	fiber.element_type = type
	fiber.type = resolved_type
	return fiber
end

function M.create_root(...)
	return M.create(FiberTag.ROOT, ...)
end

return M
