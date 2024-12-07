local markup = require("markup.core")
local log = require("markup.logger") ---@diagnostic disable-line: unused-local

return function(component)
	return function(props)
		return markup.create_element(component, props)
	end
end
