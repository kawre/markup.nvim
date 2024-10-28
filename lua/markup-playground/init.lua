local playground = {}

function playground.open()
	local api = vim.api
	vim.cmd("$tabe playground.lua")

	playground.editor = {
		winid = api.nvim_get_current_win(),
		bufnr = api.nvim_get_current_buf(),
	}

	vim.cmd("vsp preview")
	playground.preview = {
		winid = api.nvim_get_current_win(),
		bufnr = api.nvim_get_current_buf(),
	}

	api.nvim_set_current_win(playground.editor.winid)

	vim.api.nvim_create_autocmd("BufWritePost", {
		callback = function()
			local ok, err = pcall(vim.cmd.luafile, "playground.lua")
			if not ok then
				print(err)
			end
		end,
	})
end

return playground
