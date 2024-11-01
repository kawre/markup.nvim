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

---@private
markup.elements = {
	Box = "markup.box",
	Inline = "markup.inline",
	Block = "markup.block",
	Renderer = "markup.renderer",
	Window = "markup.core.window",
	Element = "markup.core.element",
	Text = "markup.core.text",
	Object = "markup.core.object",
}

return setmetatable(markup, {
	__index = function(t, k)
		if t.elements[k] then
			return require(t.elements[k])
		end
	end,
})
