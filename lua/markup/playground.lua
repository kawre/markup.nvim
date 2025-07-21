local api = vim.api

local path = vim.fn.stdpath("data") .. "/markup/lua/playground"
local file = path .. "/init.lua"

---@class markup.playground
local M = {}

function M.open()
	vim.fn.mkdir(path, "p")
	vim.cmd.tabe(file)
	vim.cmd.tcd(path)

	M.preview = Markup.renderer({
		-- ns_id = api.nvim_create_namespace("markup.playground"),
		-- enter = false,
		-- show = true,
		position = "right",
		width = 0.5,
		enter = false,
		-- config = {
		-- 	relative = "editor",
		-- 	vertical = true,
		-- 	width = 0.5,
		-- },
	})
	Markup.devkit.inspect.open(M.preview)

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
	Markup.devkit.inspect.draw("fiber")
end

return M
