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
local Enum = {}
Enum.__index = Enum

Enum.__newindex = function(tbl, key, value)
	rawset(tbl, key, flatten(value))
end

function Enum:map(enum, fn)
	local res = {}
	for k, v in pairs(enum) do
		res[k] = fn(k, v)
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

return function()
	return setmetatable({}, Enum)
end
