local log = require("markup.logger") ---@diagnostic disable-line: unused-local

local function flatten(tbl)
	local res = {}

	local function dfs(t)
		for k, v in pairs(t) do
			if type(v) == "table" then
				dfs(v)
			else
				k = k:upper()
				assert(not res[k], "Duplicate key: " .. k)
				res[k] = v
			end
		end
	end
	dfs(tbl)

	return res
end

---@class markup.Enum
---@field Lookup? table
local Enum = setmetatable({}, {
	__call = function(self)
		return setmetatable({}, self)
	end,
})
Enum.__name = "markup.collection.enum"

Enum.__index = Enum

Enum.__newindex = function(tbl, key, value)
	rawset(tbl, key, flatten(value))
end

function Enum:map(enum, fn)
	local res = {}
	for k, v in pairs(enum) do
		res[k] = fn(v, k)
	end
	return res
end

function Enum:lookup(key)
	if self.Lookup then
		local v = self.Lookup[key:upper()]
		assert(v, ("lookup: key '%s' not found"):format(key))

		if type(v) == "string" then
			return require(v)
		else
			return v
		end
	end
end

-- Bind an enum lookup table to a class
function Enum.bind(enum, class)
	class = class or {}
	local mt = getmetatable(class) or {}

	mt.__index = function(_, k)
		local v = enum[k:upper()]
		assert(v, ("lookup: key '%s' not found"):format(k))
		if type(v) == "string" then
			return require(v)
		else
			return v
		end
	end

	return setmetatable(class, mt)
end

return Enum
