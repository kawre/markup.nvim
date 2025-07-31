---@class markup.list : tablelib
---@overload fun(tbl?: table): markup.list
local M = {}
M.__index = M

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
	return M(vim.tbl_map(apply, self))
end

function M:filter(fn)
	return M(vim.tbl_filter(fn, self))
end

function M:isempty()
	return vim.tbl_isempty(self)
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
function M:foreach(fn)
	for i, v in ipairs(self) do
		self[i] = fn(v, i)
	end
end

-- vim.tbl_extend(behavior, ...)

---@param i? integer
---@param j? integer
function M:unpack(i, j)
	return unpack(self, i, j)
end

function M:reduce(fn, initial)
	local acc = initial
	local startIndex = 1
	if acc == nil then
		acc = self[1]
		startIndex = 2
	end
	for i = startIndex, #self do
		acc = fn(acc, self[i], i)
	end
	return acc
end

function M:find(fn)
	for i, v in ipairs(self) do
		if fn(v, i) then
			return v
		end
	end
	return nil
end

function M:findidx(fn)
	for i, v in ipairs(self) do
		if fn(v, i) then
			return i
		end
	end
	return -1
end

function M:some(fn)
	for i, v in ipairs(self) do
		if fn(v, i) then
			return true
		end
	end
	return false
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
