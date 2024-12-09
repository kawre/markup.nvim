local log = require("markup.logger") ---@diagnostic disable-line: unused-local
local Collection = require("markup.core.enum").Collection

---@class markup.Array : tablelib
local Array = setmetatable({}, {
	__call = function(self, tbl)
		if tbl then
			if type(tbl) == "table" then
				if not vim.islist(tbl) then
					error("Expected contiguous array")
				end
			else
				error("Expected array or nil, got " .. type(tbl))
			end
		end

		return setmetatable(tbl or {}, self)
	end,
})
Array.__name = Collection.ARRAY

---@private
function Array:__index(key)
	return Array[key] or table[key]
end

---@param fn fun(v: any, i: integer): any
---@param in_place? boolean
---@return markup.Array
function Array:map(fn, in_place)
	local arr = in_place and self or Array()

	for i, v in ipairs(self) do
		arr[i] = fn(v, i)
	end

	return arr
end

function Array:push(...)
	for _, value in ipairs({ ... }) do
		if value then
			self:insert(value)
		end
	end
end

function Array:pop()
	return self:remove()
end

---@alias markup.Array.constructor fun(init?: table): markup.Array

---@type markup.Array.constructor
return Array
