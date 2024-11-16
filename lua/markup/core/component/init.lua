---@alias markup.Component.render fun(self): markup.Node

---@alias markup.Component.Functional.constructor fun(render: markup.Component.render)
---@alias markup.Component.Class.constructor fun(props: {render: markup.Component.render})

---@alias markup.Component.constructor
---| markup.Component.Functional.constructor
---| markup.Component.Class.constructor
local log = require("markup.logger") ---@diagnostic disable-line: unused-local

---@class markup.Component
local Component = {}
Component.__index = Component

function Component:init(...)
	self.props = ...
end

---@type markup.Component.constructor
return setmetatable({}, {
	__call = function(_, content)
		if type(content) == "function" then
			content = { render = content }
		end

		return function(...)
			local instance = setmetatable(content, Component)
			instance:init(...)
			local element = instance:render()
			-- element.component = instance
			return element
		end
	end,
})
