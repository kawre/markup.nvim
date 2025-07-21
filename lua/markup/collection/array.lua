---@class markup.array : tablelib
---@overload fun(tbl?: table): markup.array
local M = {}
M.__index = M

setmetatable(M, {
	__call = function(_, tbl)
		return M.new(tbl)
	end,
	__index = function(_, k)
		return table[k]
	end,
})

function M.new(tbl)
	return setmetatable(tbl or {}, M)
end

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

function M:extend(src, start, finish)
	return vim.list_extend(self, src, start, finish)
end

function M:foreach(fn)
	for i, v in ipairs(self) do
		self[i] = fn(v, i)
	end
end

return M
