local markup = require("markup.core")
local log = require("markup.logger") ---@diagnostic disable-line: unused-local

---@alias markup.create_component
---| fun(component: table|function): fun(props: markup.create_element.props): markup.Element.Table

---@type markup.create_component
local function create_component(component)
	return function(props)
		return markup.create_element(component, props)
	end
end

return create_component
