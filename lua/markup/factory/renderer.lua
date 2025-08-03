---@class markup.Renderer.Root
---@field owner markup.renderer
---@field current markup.fiber
---@field deletions markup.fiber[]

---@alias markup.create_renderer_root
---| fun(renderer: markup.renderer, element: markup.element): markup.Renderer.Root

local M = {}

---@type markup.create_renderer_root
function M.create_root(renderer, element)
	local dom = renderer.dom
	return {
		owner = renderer,
		current = Markup.factory.fiber.root(dom, element),
		width = vim.api.nvim_win_get_width(renderer.win.id),
		height = vim.api.nvim_win_get_height(renderer.win.id),
	}
end

return M
