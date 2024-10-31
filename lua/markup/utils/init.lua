local markup = require("markup")

local utils = {}

function utils.buf_set_opts(bufnr, options)
	if not vim.api.nvim_buf_is_valid(bufnr) then
		return
	end

	for opt, value in pairs(options) do
		local ok, err = pcall(vim.api.nvim_set_option_value, opt, value, { buf = bufnr })
		if not ok then
			print(err)
		end
	end
end

function utils.win_set_opts(winid, options)
	if not vim.api.nvim_win_is_valid(winid) then
		return
	end

	for opt, value in pairs(options) do
		local ok, err = pcall(vim.api.nvim_set_option_value, opt, value, { win = winid, scope = "local" })
		if not ok then
			print(err)
		end
	end
end

function utils.is_instance(object, class)
	if not object then
		return false
	end

	return markup.Object.is_instance(object, class)
end

return utils
