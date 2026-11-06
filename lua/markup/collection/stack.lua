---@class markup.stack
---@field len integer
---@overload fun(): markup.stack
local M = Markup.object("stack")

function M:new()
	self.len = 0
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
