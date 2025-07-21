local visualizer = require("markup.dev-tools.visualizer")
local log = require("markup.logger") ---@diagnostic disable-line: unused-local

local M = {}

---@type integer
local win
---@type integer
local buf
local ns = vim.api.nvim_create_namespace("markup_inspector")
---@type markup.Renderer
local renderer
local page

function M.open(_renderer)
	renderer = _renderer
	vim.api.nvim_win_call(renderer.id, function()
		vim.cmd("split | enew | setlocal buftype=nofile bufhidden=hide noswapfile")
		win = vim.api.nvim_get_current_win()
		buf = vim.api.nvim_get_current_buf()
	end)

	vim.wo[win].number = false
	vim.wo[win].relativenumber = false
	vim.wo[win].signcolumn = "no"
	vim.wo[win].winhighlight =
		"Normal:MarkupNormal,NormalNC:MarkupNormalNC,WinBar:MarkupWinBar,WinBarNC:MarkupWinBarNC"

	vim.keymap.set("n", "1", function()
		M.draw("fiber")
	end)
	vim.keymap.set("n", "2", function()
		M.draw("node")
	end)
	vim.keymap.set("n", "3", function()
		M.draw("render")
	end)
	vim.keymap.set("n", "4", function()
		Markup.debug_mode = not Markup.debug_mode
		M.draw()
	end)
end

function M.draw(_page, opts)
	if not renderer.root then
		return
	end
	page = _page or (page or "fiber")

	local lines
	if page == "node" then
		lines = visualizer[page](renderer.root.current.state_node, opts)
	elseif page == "fiber" then
		lines = visualizer[page](renderer.root.current, opts)
	elseif page == "render" then
		lines = visualizer[page](renderer.root.current.state_node.render_box, opts)
	end

	local width = vim.api.nvim_win_get_width(win)
	local nav = {
		{ "Fiber Tree", page == "fiber" and "IncSearch" or "Conceal" },
		{ "Node Tree", page == "node" and "IncSearch" or "Conceal" },
		{ "Render Tree", page == "render" and "IncSearch" or "Conceal" },
		{ "Toggle debug mode", Markup.debug_mode and "Search" or "Conceal" },
	}

	local nav_width = 0
	for i, item in ipairs(nav) do
		item[1] = (" (%d) %s "):format(i, item[1])
		nav_width = nav_width + vim.fn.strdisplaywidth(item[1])
	end

	-- table.insert(nav, 1, { (" "):rep(math.floor(width - nav_width) / 2) })
	table.insert(lines, 1, {})
	table.insert(lines, 1, nav)

	vim.api.nvim_buf_call(buf, function()
		vim.api.nvim_buf_clear_namespace(0, ns, 0, -1)
		for l, line in ipairs(lines or {}) do
			vim.api.nvim_buf_set_lines(0, l - 1, l, false, { "" })
			vim.api.nvim_buf_set_extmark(0, ns, l - 1, 0, {
				virt_text = line,
				virt_text_pos = "overlay",
			})
		end
	end)
end

return M
