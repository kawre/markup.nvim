local api = vim.api
local log = require("markup.logger") ---@diagnostic disable-line: unused-local

local path = vim.fn.stdpath("data") .. "/markup/lua/playground"
local file = path .. "/init.lua"

---@class markup-playground
local playground = {}

function playground.open()
	local markup = require("markup")

	vim.fn.mkdir(path, "p")
	vim.cmd.tabe(file)
	vim.cmd.tcd(path)

	playground.editor = markup.Window({
		id = 0,
		bufnr = 0,
		filename = path,
		minimal = false,
	})

	playground.preview = markup.Renderer({
		ns_id = api.nvim_create_namespace("markup-playground"),
		enter = false,
		show = true,
		position = "right",
		config = {
			relative = "editor",
			vertical = true,
			width = 0.5,
		},
	})

	vim.api.nvim_create_autocmd("BufWritePost", {
		callback = function()
			vim.schedule(function()
				local ok, err = pcall(vim.cmd.luafile, file)
				if not ok then
					log.error(err)
				end
			end)
		end,
	})
end

function playground.run()
	-- ---@module 'snacks'
	-- Snacks.profiler.start()
	vim.cmd("luafile " .. file)
	-- Snacks.profiler.stop()
end

function playground.generate_test()
	local buf_lines = {}

	local lines = playground.preview:buf_get_lines(0, -1, false)
	for _, line in ipairs(lines) do
		table.insert(buf_lines, ("\"%s\","):format(line))
	end

	local extmarks = playground.preview:buf_get_extmarks(0, -1, {})

	log.debug(table.concat(buf_lines, "\n"))
	log.debug(extmarks)
end

function playground.setup()
	vim.api.nvim_create_user_command("Markup", playground.open, {})
	vim.api.nvim_create_user_command("MarkupRun", playground.run, {})
	vim.api.nvim_create_user_command("MarkupGenTest", playground.generate_test, {})
end

return playground
