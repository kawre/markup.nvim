---@class markup.stack
---@field len integer
---@overload fun(): markup.stack
local M = setmetatable({}, {
	__call = function(t)
		return t.new()
	end,
})
M.__index = M

---@return markup.stack
function M.new()
	return setmetatable({ len = 0 }, M)
end

function M:push(value)
	if value == nil then
		return
	end
	self.len = self.len + 1
	self[self.len] = value
end

function M:pop()
	assert(self.len > 0, "stack is empty")
	local value = self[self.len]
	self[self.len] = nil
	self.len = self.len - 1
	return value
end

function M:peek()
	return self[self.len]
end

return M
