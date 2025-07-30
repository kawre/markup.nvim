local M = Markup.singleton()

---@alias markup.hooks.window
---| fun(): markup.window

function M.call()
	local renderer = Markup.renderer.current
	assert(renderer, "`view` hook must be called within a renderer context")
	return renderer.win
end

return M
