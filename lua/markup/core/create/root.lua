local markup = require("markup.core")

local function create_root()
	return markup.create_element("inline")
end

return create_root
