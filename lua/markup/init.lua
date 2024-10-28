---@class markup
---@field Box markup.Box.constructor
---@field Inline markup.Inline.constructor
---@field Block markup.Block.constructor
---@field Renderer markup.Renderer.constructor
---@field Window markup.Window.constructor
---@field Element markup.Element.constructor
---@field Text markup.Text.constructor
---@field Object markup.Object.constructor
local markup = {}

markup.elements = {
	Box = "box",
	Inline = "inline",
	Block = "block",
	Renderer = "renderer",
	Window = "core.window",
	Element = "core.element",
	Text = "core.text",
	Object = "core.object",
}

return setmetatable(markup, {
	__index = function(t, k)
		if t.elements[k] then
			return require("markup." .. t.elements[k])
		end
	end,
})
