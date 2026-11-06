local path = vim.fn.stdpath("data") .. "/markup/lua/playground"
local file = path .. "/init.lua"

---@class markup.playground
local M = {}

---@param opts? { inspect?: boolean } set `inspect = false` to skip the inspector
function M.open(opts)
	opts = opts or {}

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

	M.inspect = nil
	if opts.inspect ~= false then
		M.inspect = Markup.devkit.inspect({
			win = M.preview.win.win,
			relative = "editor",
			position = "right",
			width = 0.4,
		})
		M.inspect:map(buf)
	end

	local function run()
		local ok, err = pcall(M.run)
		if not ok then
			Markup.log.error(err)
		end
	end

	vim.api.nvim_create_autocmd("BufWritePost", {
		buffer = buf,
		callback = function()
			vim.schedule(run)
		end,
	})

	vim.schedule(run)
end

function M.run()
	vim.cmd("luafile " .. file)
end

return M
