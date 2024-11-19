local Class = require("markup.core.node.component.class")
local markup = require("markup")

---@class markup.Component : markup.Node
local Component = markup.Node:extend("markup.component") ---@diagnostic disable-line: undefined-field

function Component:init(object)
	if type(object) == "function" then
		object = { render = object }
	end

	self.object = setmetatable(object, Class)
	self.object:init()

	Component.super.init(self, {
		type = "component",
	})
end

function Component:set_props(props)
	self.object.props = props
	return self
end

function Component:render()
	self.element = self.object:render()
	self.object._element = self.element
	return self.element
end

return setmetatable({}, {
	__call = function(_, object)
		local instance = Component(object)
		return function(...)
			return instance:set_props(...)
		end
	end,
})
