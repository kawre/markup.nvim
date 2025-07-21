---@class markup.config
local M = {
	user = {
		logging = true,
	},
	name = "markup.nvim",
	debug = false,
	randomseed = 1753102604,
}

---@param opts? table
function M.merge(opts)
	opts = opts or {}
	if not vim.tbl_isempty(opts) then
		M.user = vim.tbl_deep_extend("force", M.user, opts)
	end
end

return M
