local log = require("markup.logger") ---@diagnostic disable-line: unused-local
local markup = require("markup.core")
local FiberTag = require("markup.core.fiber.enum").Tag
local u = require("markup.utils")

local function tag_from_type(etype)
	if type(etype) == "function" then
		return FiberTag.FUNCTION
	elseif type(etype) == "table" and type(etype.render) == "function" then
		return FiberTag.CLASS
	elseif u.is_class(etype, markup.Element) then
		return FiberTag.ELEMENT
	elseif u.is_class(etype, markup.Text) then
		return FiberTag.TEXT
	else
		error("Unknown element type " .. etype)
	end
end

---@alias markup.create_fiber
---| fun(type: markup.Fiber.type, props: any, key?: string): markup.Fiber

---@type markup.create_fiber
local function create_fiber(type, props, key)
	return {
		pending_props = props,
		type = type,
		key = key,
		tag = tag_from_type(type),
		alternate = nil,
		flag = nil,
		index = 1,
	}
end

return create_fiber
