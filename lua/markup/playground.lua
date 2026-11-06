local path = vim.fn.stdpath("data") .. "/markup/lua/playground"

---@class markup.playground
local M = {}

---@class markup.playground.opts
---@field inspect? boolean set to `false` to skip the inspector
---@field view? boolean render with `Markup.view` instead of the old renderer
---@field file? string file in the playground folder, `init.lua` by default

---@param opts? markup.playground.opts
function M.open(opts)
	opts = opts or {}
	M.file = path .. "/" .. (opts.file or "init.lua")

	vim.fn.mkdir(path, "p")
	vim.cmd.tabe(M.file)
	vim.cmd.tcd(path)
	local buf = vim.api.nvim_get_current_buf()

	local win = Markup.window({
		enter = false,
		relative = "win",
		position = "bottom",
	})
	M.preview = opts.view and Markup.view(win) or Markup.renderer(win)

	M.inspect = nil
	if opts.inspect ~= false and not opts.view then
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
	vim.cmd("luafile " .. M.file)
end

return M
