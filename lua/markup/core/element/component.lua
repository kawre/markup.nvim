local markup = require("markup")
local log = require("markup.logger") ---@diagnostic disable-line: unused-local

return function(component)
	return function(props)
		return markup.Element2(component, props)
	end
end
