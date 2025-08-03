---@alias markup.object
---| fun(mt?: metatable): {}

---@param mt metatable
return function(mt)
	mt = vim.tbl_extend("keep", {
		__call = function(t, ...)
			local self = setmetatable({}, t)
			assert(t.new, "Object must have a 'new' method")
			t.new(self, ...)
			return self
		end,
		__type = ("markup.%s"):format(type or "object"),
	}, mt or {})

	local M = setmetatable({}, mt)
	M.__index = M

	return M
end
