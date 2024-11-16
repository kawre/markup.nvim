local markup = require("markup")

return setmetatable({}, {
	__call = function(_, cond, node)
		if cond and node then
			if type(node) == "function" then
				node = node()
			end

			if type(node) == "table" then
				return unpack(node)
			else
				return node
			end
		else
			return markup._
		end
	end,
})
