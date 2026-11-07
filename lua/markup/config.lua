---@class markup.config
local M = {
	user = {
		logging = true,
		inspector = {
			--- Marks the element selected in the inspector inside the view itself.
			--- Toggle it with `m` while the inspector is open.
			mark = true,
		},
	},
	name = "markup.nvim",
	debug = false,
}

local is_dict_like = function(v) -- has string and number keys
	return type(v) == "table" and (vim.tbl_isempty(v) or not vim.islist(v))
end
local is_dict = function(v) -- has only string keys
	return type(v) == "table" and (vim.tbl_isempty(v) or not v[1])
end

--- Merges the values similar to vim.tbl_deep_extend with the **force** behavior,
--- but the values can be any type
---@generic T
---@param ... T
---@return T
function M.merge(...)
	local ret = select(1, ...)
	for i = 2, select("#", ...) do
		local value = select(i, ...)
		if is_dict_like(ret) and is_dict(value) then
			for k, v in pairs(value) do
				ret[k] = M.merge(ret[k], v)
			end
		elseif value ~= nil then
			ret = value
		end
	end
	return ret
end

return M
