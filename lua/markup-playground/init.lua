local log = require("markup.logger") ---@diagnostic disable-line: unused-local

---@class markup-playground
local playground = {}

function playground.open()
	local markup = require("markup")
	local path = vim.fn.stdpath("data") .. "/markup/playground.lua"
	local api = vim.api

	vim.cmd.tabe(path)
	local bufnr, winid = api.nvim_get_current_buf(), api.nvim_get_current_win()

	playground.editor = {
		winid = winid,
		bufnr = bufnr,
		filename = api.nvim_buf_get_name(bufnr),
	}

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
			local ok, err = pcall(vim.cmd.luafile, playground.editor.filename)
			if not ok then
				log.error(err)
			else
				playground.preview:render()
			end
		end,
	})
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
	vim.api.nvim_create_user_command("MarkupGenTest", playground.generate_test, {})
end

return playground
