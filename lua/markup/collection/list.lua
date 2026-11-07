---@class markup.list : tablelib
---@overload fun(tbl?: table): markup.list
local M = {}
M.__index = M
M.__type = "markup.list"

setmetatable(M, { ---@diagnostic disable-line: param-type-mismatch
	__call = function(_, tbl)
		return M.new(tbl)
	end,
	__index = function(_, k)
		return table[k]
	end,
})

function M.new(tbl)
	return setmetatable(tbl or {}, M) ---@diagnostic disable-line: param-type-mismatch
end

-- Returns a new array with the values of the current array.
function M:map(apply)
	local tbl = {}
	for i, v in ipairs(self) do
		tbl[i] = apply(v, i)
	end
	return M(tbl)
end

function M:filter(fn)
	return M(vim.tbl_filter(fn, self))
end

function M:contains(value)
	return vim.list_contains(self, value)
end

---@param ...table
function M:extend(...)
	local dest = {}

	for _, tbl in ipairs({ self, ... }) do
		if type(tbl) == "table" then
			for _, v in ipairs(tbl) do
				table.insert(dest, v)
			end
		end
	end

	return M(dest)
end

-- Replaces values with the result of applying the function to each value.

-- vim.tbl_extend(behavior, ...)

---@param i? integer
---@param j? integer
function M:unpack(i, j)
	return unpack(self, i, j)
end

function M:find(fn)
	for i, v in ipairs(self) do
		if fn(v, i) then
			return v
		end
	end
	return nil
end

function M:every(fn)
	for i, v in ipairs(self) do
		if not fn(v, i) then
			return false
		end
	end
	return true
end

return M
