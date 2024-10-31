---@class markup-playground
local playground = {}

function playground.open()
	local path = vim.fn.stdpath("data") .. "/markup" .. "/playground.lua"

	local api = vim.api
	vim.cmd("$tabe" .. path)

	playground.editor = {
		winid = api.nvim_get_current_win(),
		bufnr = api.nvim_get_current_buf(),
	}
	playground.editor.filename = api.nvim_buf_get_name(playground.editor.bufnr)

	vim.cmd("vsp preview")
	playground.preview = {
		winid = api.nvim_get_current_win(),
		bufnr = api.nvim_get_current_buf(),
	}

	api.nvim_set_current_win(playground.editor.winid)

	vim.api.nvim_create_autocmd("BufWritePost", {
		callback = function()
			local ok, err = pcall(vim.cmd.luafile, playground.editor.filename)
			if not ok then
				local log = require("markup.logger")
				log.error(err)
			end
		end,
	})
end

function playground.setup()
	vim.api.nvim_create_user_command("Markup", playground.open, {})
end

return playground
