local log = require("markup.logger") ---@diagnostic disable-line: unused-local
local Collection = require("markup.core.enum").Collection

---@class markup.Array : tablelib
local Array = setmetatable({}, {
	__call = function(self, tbl)
		return setmetatable(tbl or {}, self)
	end,
	__name = Collection.ARRAY,
})

function Array:__index(key)
	return Array[key] or table[key]
end

function Array:map(fn)
	local res = Array()

	for i, v in ipairs(self) do
		res[i] = fn(v, i)
	end

	return res
end

---@alias markup.Array.constructor fun(table: table): markup.Array

---@type markup.Array.constructor
return Array
