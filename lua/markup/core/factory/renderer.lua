local FiberFactory = require("markup.core.factory.fiber")
local log = require("markup.logger")

---@class markup.Renderer.Root
---@field owner markup.Renderer
---@field current markup.Fiber

---@alias markup.create_renderer_root
---| fun(renderer: markup.Renderer, element: markup.Element): markup.Renderer.Root

local M = {}

---@type markup.create_renderer_root
function M.create_root(renderer, element)
	return {
		owner = renderer,
		current = FiberFactory.create_root(element),
		width = vim.api.nvim_win_get_width(renderer.id),
		height = vim.api.nvim_win_get_height(renderer.id),
	}
end

return M
