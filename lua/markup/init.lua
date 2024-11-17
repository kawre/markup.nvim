local core = require("markup.core")
local ui = require("markup.ui")

---@class markup
-- Object
---@field Object markup.Object.constructor
-- Node
---@field Node markup.Node.constructor
---@field Brake markup.Node.constructor
---@field Text markup.Text.constructor
---@field Pad markup.Padding.constructor
-- Element
---@field Element markup.Element.constructor
-- Inline
---@field Inline markup.Inline.constructor
---@field Anchor markup.Inline.constructor
---@field Code markup.Inline.constructor
---@field Italic markup.Inline.constructor
---@field Mark markup.Inline.constructor
---@field Strike markup.Inline.constructor
---@field Strong markup.Inline.constructor
---@field Sub markup.Inline.constructor
---@field Sup markup.Inline.constructor
---@field Underline markup.Inline.constructor
-- Block
---@field Block markup.Block.constructor
---@field Flex markup.Flex.constructor
---@field HFlex markup.Flex.constructor
---@field Box markup.Flex.constructor
---@field Grid markup.Grid.constructor
---@field List markup.List.constructor
---@field OList markup.List.constructor
---@field ListItem markup.Block.constructor
---@field Pre markup.Pre.constructor
-- Window
---@field Window markup.Window.constructor
---@field Renderer markup.Renderer.constructor
---@field RendererLine markup.Renderer.Line.constructor
-- TabPage
---@field TabPage markup.TabPage.constructor
-- Component
---@field Component markup.Component.constructor
-- Parser
---@field Parser markup.Parser.constructor
-- Utils
---@field If markup.If.constructor
---@field Fragment markup.Fragment.constructor
local markup = {}

---@private
markup.lookups = {}
---@private
markup.modules = { core, ui }

---@param lookups table<string, string>
function markup.register(lookups)
	for name, path in pairs(lookups) do
		markup.lookups[name] = path
	end
end

for _, module in ipairs(markup.modules) do
	markup.register(module.lookups)
end

function markup.setup(opts)
	local config = require("markup.config")

	config.user = vim.tbl_deep_extend("force", config, opts or {})
	config.debug = opts.debug or config.debug

	require("markup-playground").setup()
end

return setmetatable(markup, {
	__index = function(t, k)
		if t.lookups[k] then
			return require(t.lookups[k])
		end
	end,
})
