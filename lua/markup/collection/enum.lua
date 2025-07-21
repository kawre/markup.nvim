local function flatten(tbl)
	local res = {}

	local function dfs(t)
		for k, v in pairs(t) do
			if type(v) == "table" then
				dfs(v)
			else
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

-- Create a lookup table for the enum
---@param enum? table
function Enum:bind(enum)
	enum = enum or self.Lookup
	assert(enum, "`Enum.Lookup` table is required")

	return setmetatable({}, {
		__index = function(_, k)
			local v = enum[k:upper()]
			assert(v, ("lookup: key '%s' not found"):format(k))
			if type(v) == "string" then
				return require(v)
			else
				return v
			end
		end,
	})
end

return Enum
