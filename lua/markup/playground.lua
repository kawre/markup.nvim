local path = vim.fn.stdpath("data") .. "/markup/lua/playground"
local file = path .. "/init.lua"

---@class markup.playground
local M = {}

function M.open()
	vim.fn.mkdir(path, "p")
	vim.cmd.tabe(file)
	vim.cmd.tcd(path)
	local buf = vim.api.nvim_get_current_buf()

	M.preview = Markup.renderer({ enter = false })

	M.inspect = Markup.devkit.inspect({
		win = M.preview.win.win,
		position = "bottom",
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
