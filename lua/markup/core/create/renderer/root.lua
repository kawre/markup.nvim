local markup = require("markup.core")

---@class markup.Renderer.Root
---@field owner markup.Renderer
---@field current markup.Fiber

---@alias markup.create_renderer_root
---| fun(renderer: markup.Renderer, element: markup.xElement): markup.Renderer.Root

---@type markup.create_renderer_root
local function create_renderer_root(renderer, element)
	return {
		owner = renderer,
		current = markup.create_fiber_root(element),
	}
end

return create_renderer_root
