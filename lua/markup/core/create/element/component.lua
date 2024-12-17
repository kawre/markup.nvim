local markup = require("markup.core")
local log = require("markup.logger") ---@diagnostic disable-line: unused-local

---@alias markup.create_component
---| fun(Component: table|function): fun(props?: markup.create_element.props, any...): markup.xElement

---@type markup.create_component
local function create_component(Component)
	return function(...)
		local element = markup.create_element(Component, ...)
		return element
	end
end

return create_component
