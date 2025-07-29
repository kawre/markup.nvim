---@alias markup.hooks.window
---| fun(): markup.window

local function window()
	local renderer = Markup.renderer.current
	assert(renderer, "`view` hook must be called within a renderer context")
	return renderer.win
end

return window
