local log = require("markup.logger") ---@diagnostic disable-line: unused-local
local Class = require("markup.core.node.component.class")
local markup = require("markup")

---@class markup.Component : markup.Node
local Component = markup.Node:extend("markup.component.instance") ---@diagnostic disable-line: undefined-field

function Component:init(object, ...)
	self.instance = setmetatable(object, Class)
	self.instance:init(...)
	self.element = nil

	Component.super.init(self, {
		type = "component",
	})
end

function Component:render()
	self.element = markup.Fragment(self.instance:render())
	self.instance.node = self.element
	return self.element
end

---@alias markup.Component.constructor fun(...): fun(...): markup.Component

---@type markup.Component.constructor
return function(object)
	if type(object) == "function" then
		object = { render = object }
	end

	return function(...)
		return Component(vim.deepcopy(object), ...)
	end
end
