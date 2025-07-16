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
	vim.api.nvim_buf_call(playground.preview.bufnr, function()
		vim.cmd("split | enew | setlocal buftype=nofile bufhidden=hide noswapfile")
		playground.preview.sid = vim.api.nvim_get_current_win()
		playground.preview.sbuf = vim.api.nvim_get_current_buf()
		playground.preview.set_opts(
			{
				id = playground.preview.sid,
				buf = playground.preview.sbuf,
			},
			nil,
			{
				winhighlight = "Normal:MarkupNormal,NormalNC:MarkupNormalNC,WinBar:MarkupWinBar,WinBarNC:MarkupWinBarNC",
				cursorcolumn = false,
				cursorline = false,
				cursorlineopt = "both",
				fillchars = "eob: ,lastline:…",
				list = false,
				listchars = "extends:…,tab:  ",
				number = false,
				relativenumber = false,
				signcolumn = "no",
				spell = false,
				winbar = "",
				statuscolumn = "",
				wrap = false,
				sidescrolloff = 0,
				foldenable = false,
				foldcolumn = "0",
				colorcolumn = "",
				winfixbuf = true,
			}
		)
	end)

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
	vim.api.nvim_create_user_command("MarkupDev", function()
		require("markup.dev-tools.picker")()
	end, {})
	vim.api.nvim_create_user_command("MarkupDevFiber", function()
		local pick = require("markup.dev-tools.picker.pick")
		local items = require("markup.dev-tools.picker.fiber-tree")(playground.preview.root.current)
		pick({ items = items })
	end, {})
	vim.keymap.set("n", "<leader>mf", "<cmd>MarkupDevFiber<cr>", { noremap = true, silent = true })
	-- vim.keymap.set("n", "<leader>mn", "<cmd>MarkupDevFiber<cr>", { noremap = true, silent = true })
	-- vim.keymap.set("n", "<leader>mr", "<cmd>MarkupDevFiber<cr>", { noremap = true, silent = true })
	vim.api.nvim_create_user_command("MarkupGenTest", playground.generate_test, {})
end

return playground
