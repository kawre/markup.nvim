local markup = require("markup.core")
local FiberTag = require("markup.core.fiber.enum").Tag
local u = require("markup.utils")

local function tag_from_type(_type)
	local type = type(_type)

	if type == "function" then
		return FiberTag.FUNCTION
	elseif u.is_class(type, markup.Element) then
		return FiberTag.ELEMENT
	elseif u.is_class(type, markup.Text) then
		return FiberTag.TEXT
	else
		error("Unknown element type: " .. type)
	end
end

---@alias markup.create_fiber
---| fun(type: any, pending_props: table, key?: string): markup.Fiber

---@type markup.create_fiber
local function create_fiber(type, pending_props, key)
	return {
		props = pending_props,
		type = type,
		tag = tag_from_type(type),
		index = 0,
		alternate = nil,
		key = key,
	}
end

return create_fiber
