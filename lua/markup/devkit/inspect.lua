---@class markup.devkit.inspect
---@field renderer markup.renderer
local M = {}

local ns = vim.api.nvim_create_namespace("markup_inspector")

function M.open(renderer)
	M.renderer = renderer
	M.win = Markup.window({
		position = "right",
		minimal = true,
		enter = false,
	})

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
		Markup.config.debug = not Markup.config.debug
		M.draw()
	end)
end

function M.draw(page, opts)
	if not M.renderer.rootf then
		return
	end
	page = page or (M.page or "fiber")

	local lines
	if page == "node" then
		lines = Markup.devkit.visualizer[page](M.renderer:node_root(), opts)
	elseif page == "fiber" then
		lines = Markup.devkit.visualizer[page](M.renderer:fiber_root(), opts)
	elseif page == "render" then
		lines = Markup.devkit.visualizer[page](M.renderer:render_root(), opts)
	end

	local nav = {
		{ "Fiber Tree", page == "fiber" and "IncSearch" or "Conceal" },
		{ "Node Tree", page == "node" and "IncSearch" or "Conceal" },
		{ "Render Tree", page == "render" and "IncSearch" or "Conceal" },
		{ "Toggle debug mode", Markup.config.debug and "Search" or "Conceal" },
	}

	for i, item in ipairs(nav) do
		item[1] = (" (%d) %s "):format(i, item[1])
	end

	table.insert(lines, 1, {})
	table.insert(lines, 1, nav)

	vim.api.nvim_buf_call(M.win.buf, function()
		vim.api.nvim_buf_clear_namespace(0, ns, 0, -1)
		for l, line in ipairs(lines or {}) do
			vim.api.nvim_buf_set_lines(0, l - 1, l, false, { "" })
			vim.api.nvim_buf_set_extmark(0, ns, l - 1, 0, {
				virt_text = line,
				virt_text_pos = "overlay",
			})
		end
	end)

	M.page = page
end

return M
