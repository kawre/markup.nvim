---@class markup.collection.Stack
---@field len integer
local Stack = {}

---@return markup.collection.Stack
function Stack.new()
	return { len = 0 }
end

function Stack:push(value)
	if value == nil then
		return
	end
	self.len = self.len + 1
	self[self.len] = value
end

function Stack:pop()
	if self.len == 0 then
		return nil
	end
	local value = self[self.len]
	self[self.len] = nil
	self.len = self.len - 1
	return value
end

return Stack
