local log = require("markup.logger") ---@diagnostic disable-line: unused-local
local markup = require("markup.core")
local FiberTag = require("markup.core.reconciler.enum").Tag
local u = require("markup.utils")

---@class markup.Fiber.hook
---@field memoized_state any
---@field base_state any
---@field dispatch function
---@field last_rendered_state any
---@field next? markup.Fiber.hook

---@class markup.Fiber
---@field pending_props any
---@field memoized_props any
---@field memoized_state any
---@field type markup.Fiber.type
---@field tag markup.Fiber.tag
---@field state_node markup.Node
---@field flags integer
---@field key? any
---@field hook? markup.Fiber.hook
---@field alternate? markup.Fiber
---@field child? markup.Fiber
---@field sibling? markup.Fiber
---@field index integer

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
---| fun(type: markup.Fiber.type, props?, key?): markup.Fiber

---@type markup.create_fiber
local function create_fiber(type, props, key)
	return {
		pending_props = props,
		memoized_state = {},
		type = type,
		key = key,
		tag = tag_from_type(type),
		alternate = nil,
		flags = 0,
		index = 1,
		hook = nil,
	}
end

return create_fiber
