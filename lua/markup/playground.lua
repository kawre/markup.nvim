---@class markup.playground
---@field file? string the playground file the tab shows, which `run` runs
---@field shown? string the file the preview shows, the one saved last
---@field preview? markup.view the view below the file, for it to render into
local M = {
	--- Where the playground's files are.
	path = vim.fn.stdpath("data") .. "/markup/lua/playground",
}

--- Whether `file` is one of the playground's.
---@param file string
local function in_playground(file)
	return file ~= ""
		and vim.startswith(vim.fs.normalize(file), vim.fs.normalize(M.path) .. "/")
		and file:match("%.lua$") ~= nil
end

--- Runs `file` into the preview. Another file than the one the preview shows
--- starts from an empty preview, so one that renders nothing, such as one
--- that opens a picker, leaves nothing of the one before.
---@param file string
local function show(file)
	file = vim.fs.normalize(file)
	if file ~= M.shown and M.preview then
		M.preview:unmount()
	end
	M.file, M.shown = file, file
	local ok, err = pcall(M.run)
	if not ok then
		Markup.log.error(err)
	end
end

---@class markup.playground.opts
---@field file? string file in the playground folder, `init.lua` by default

--- Opens a file of the playground in a tab, with a preview below it, and runs
--- it. Saving a playground file runs it into the preview: switching to one
--- only makes it the one `run` runs, so nothing runs before it is saved.
---@param opts? markup.playground.opts
function M.open(opts)
	opts = opts or {}
	M.file, M.shown = nil, nil

	vim.fn.mkdir(M.path, "p")
	vim.cmd.tabe(M.path .. "/" .. (opts.file or "init.lua"))
	vim.cmd.tcd(M.path)
	local tab = vim.api.nvim_get_current_tabpage()

	local win = Markup.window({
		enter = false,
		relative = "win",
		position = "bottom",
	})
	M.preview = Markup.view(win)

	local group = vim.api.nvim_create_augroup("markup.playground", { clear = true })
	vim.api.nvim_create_autocmd("BufEnter", {
		group = group,
		callback = function(args)
			-- The buffer's full name: `args.file` is as typed, relative to the
			-- playground the tab is in.
			local file = vim.api.nvim_buf_get_name(args.buf)
			if vim.api.nvim_get_current_tabpage() == tab and in_playground(file) then
				M.file = vim.fs.normalize(file)
			end
		end,
	})
	vim.api.nvim_create_autocmd("BufWritePost", {
		group = group,
		callback = function(args)
			local file = vim.api.nvim_buf_get_name(args.buf)
			if in_playground(file) then
				vim.schedule(function()
					show(file)
				end)
			end
		end,
	})

	local file = vim.api.nvim_buf_get_name(0)
	vim.schedule(function()
		show(file)
	end)
end

--- Opens a view that keeps markup busy, with the inspector beside it.
function M.stress_test()
	return require("markup.devkit.stress").open()
end

--- Runs the playground file the tab shows.
function M.run()
	vim.cmd("luafile " .. vim.fn.fnameescape(M.file))
end

return M
