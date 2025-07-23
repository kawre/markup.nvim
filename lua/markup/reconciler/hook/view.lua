---@alias markup.view
---| fun(): markup.renderer

local function view()
	local renderer = Markup.renderer.current
	assert(renderer, "`view` hook must be called within a renderer context")

	return renderer
end

return view
