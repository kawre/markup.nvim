local log = require("markup.logger") ---@diagnostic disable-line: unused-local
local Collection = require("markup.core.enum").Collection

---@class markup.Array : tablelib
local Array = setmetatable({}, {
	__call = function(self, tbl)
		return setmetatable(tbl or {}, self)
	end,
})
Array.__name = Collection.ARRAY

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

---@alias markup.Array.constructor fun(init?: table): markup.Array

---@type markup.Array.constructor
return Array
