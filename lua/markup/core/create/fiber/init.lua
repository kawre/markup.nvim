local log = require("markup.logger") ---@diagnostic disable-line: unused-local
local markup = require("markup.core")
local FiberTag = require("markup.core.fiber.enum").Tag
local u = require("markup.utils")

local function tag_from_type(etype)
	if type(etype) == "string" then
		etype = markup[etype]
	end

	if type(etype) == "function" then
		return FiberTag.FUNCTION
	elseif u.is_class(etype, markup.Element) then
		return FiberTag.ELEMENT
	elseif u.is_class(etype, markup.Text) then
		return FiberTag.TEXT
	else
		error("Unknown element type: " .. etype)
	end
end

---@alias markup.create_fiber
---| fun(type: markup.Fiber.type, pending_props: any, key?: string): markup.Fiber

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
