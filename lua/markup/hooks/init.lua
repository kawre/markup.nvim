local M = setmetatable({}, {
	__index = function(t, k)
		t[k] = require("markup.hooks." .. k)
		return rawget(t, k)
	end,
})

return M
