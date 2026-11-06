local path = vim.fn.stdpath("data") .. "/markup/lua/playground"
local file = path .. "/init.lua"

---@class markup.playground
local M = {}

function M.open()
	vim.fn.mkdir(path, "p")
	vim.cmd.tabe(file)
	vim.cmd.tcd(path)
	local buf = vim.api.nvim_get_current_buf()

	local win = Markup.window({
		enter = false,
		relative = "win",
		position = "bottom",
	})
	M.preview = Markup.renderer(win)

	M.inspect = Markup.devkit.inspect({
		win = M.preview.win.win,
		relative = "editor",
		position = "right",
		width = 0.4,
	})
	M.inspect:map(buf)

	vim.api.nvim_create_autocmd("BufWritePost", {
		callback = function()
			vim.schedule(function()
				local ok, err = pcall(M.run)
				if not ok then
					Markup.log.error(err)
				end
			end)
		end,
	})
end

function M.run()
	vim.cmd("luafile " .. file)
end

return M
