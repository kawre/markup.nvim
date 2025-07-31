---@class markup.devkit.inspect
---@field renderer markup.renderer
---@overload fun(opts: markup.window.config): markup.devkit.inspect
local M = Markup.object()

local ns = vim.api.nvim_create_namespace("markup_inspector")

---@param opts markup.window.config
function M:new(opts)
	opts = opts or {}
	local win = opts.win or vim.api.nvim_get_current_win()
	self.renderer = Markup.renderers[win]

	opts = vim.tbl_deep_extend("keep", opts, {
		position = "right",
		relative = "win",
		minimal = true,
		enter = false,
	})
	self.win = Markup.window(opts)

	vim.api.nvim_create_autocmd("User", {
		pattern = "MarkupRender" .. self.renderer.win.id,
		callback = function()
			self:paint()
		end,
	})

	self:map(self.renderer.win.buf)
	self:map()
	self:paint()
end

function M:map(buf)
	buf = buf or self.win.buf

	vim.keymap.set("n", "1", function()
		self:paint("fiber")
	end, { buffer = buf })
	vim.keymap.set("n", "2", function()
		self:paint("node")
	end, { buffer = buf })
	vim.keymap.set("n", "3", function()
		self:paint("render")
	end, { buffer = buf })
	vim.keymap.set("n", "4", function()
		Markup.config.debug = not Markup.config.debug
		self.renderer:schedule_rerender()
	end, { buffer = buf })
end

function M:paint(page, opts)
	if not self.renderer.rootf then
		return
	end
	page = page or (self.page or "fiber")

	local lines
	if page == "node" then
		lines = Markup.devkit.visualizer[page](self.renderer:node_root(), opts)
	elseif page == "fiber" then
		lines = Markup.devkit.visualizer[page](self.renderer:fiber_root(), opts)
	elseif page == "render" then
		lines = Markup.devkit.visualizer[page](self.renderer:render_root(), opts)
	end

	local active_hl = "NeogitHunkHeaderHighlight"
	local nav = {
		{ "Fiber Tree", page == "fiber" and active_hl or "Conceal" },
		{ "Node Tree", page == "node" and active_hl or "Conceal" },
		{ "Render Tree", page == "render" and active_hl or "Conceal" },
		{ "Toggle debug mode", Markup.config.debug and "Search" or "Conceal" },
	}

	for i, item in ipairs(nav) do
		item[1] = (" (%d) %s "):format(i, item[1])
	end

	table.insert(lines, 1, {})
	table.insert(lines, 1, nav)

	table.insert(lines, 1, {})
	table.insert(lines, 1, {
		{ " Σ ", "NeogitDiffDeleteHighlight" },
		{ (" %.2f ms"):format(self.renderer.stats.elapsed) },
		{ " " },
		{ "  ", "NeogitHunkHeaderHighlight" },
		{ (" %d fps"):format(self.renderer.stats.fps) },
		{ " | ", "Conceal" },
		{ "  ", "DiagnosticVirtualTextError" },
		{ (" %.2f ms"):format(self.renderer.stats.reconciliation) },
		{ " " },
		{ "  ", "DiagnosticVirtualTextWarn" },
		{ (" %.2f ms"):format(self.renderer.stats.layout) },
		{ " " },
		{ "  ", "DiagnosticVirtualTextInfo" },
		{ (" %.2f ms"):format(self.renderer.stats.paint) },
	})

	vim.api.nvim_buf_call(self.win.buf, function()
		vim.api.nvim_buf_clear_namespace(0, ns, 0, -1)
		for l, line in ipairs(lines or {}) do
			vim.api.nvim_buf_set_lines(0, l - 1, l, false, { "" })
			vim.api.nvim_buf_set_extmark(0, ns, l - 1, 0, {
				virt_text = line,
				virt_text_pos = "overlay",
			})
		end
	end)

	self.page = page
end

return M
