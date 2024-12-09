local log = require("markup.logger") ---@diagnostic disable-line: unused-local
local enum = require("markup.core.enum")

---@class markup.core
-- Create xElement
---@field create_element markup.create_element
---@field create_component markup.create_component
---@field create_root markup.create_root
-- Create Fiber
---@field create_fiber markup.create_fiber
---@field create_fiber_root markup.create_fiber_root
---@field create_fiber_from_element markup.create_fiber_from_element
---@field create_fiber_from_text markup.create_fiber_from_text
---@field create_fiber_from_fragment markup.create_fiber_from_text
-- Create Renderer Root
---@field create_renderer_root markup.create_renderer_root
-- Object
---@field Object markup.Object.constructor
---@field Node markup.Node.constructor
---@field Text markup.Text.constructor
---@field Pad markup.Padding.constructor
---@field Element markup.Element.constructor
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
---@field Block markup.Block.constructor
---@field Flex markup.Flex.constructor
---@field HFlex markup.Flex.constructor
---@field Box markup.Flex.constructor
---@field Grid markup.Grid.constructor
---@field List markup.List.constructor
---@field OList markup.List.constructor
---@field ListItem markup.Block.constructor
---@field Pre markup.Pre.constructor
---@field Fiber markup.Fiber
---@field Window markup.Window.constructor
---@field Renderer markup.Renderer.constructor
---@field RendererLine markup.Renderer.Line.constructor
---@field RendererBuilder markup.Renderer.Builder
---@field TabPage markup.TabPage.constructor
---@field Parser markup.Parser.constructor
---@field Reconciler markup.Reconciler.constructor
-- Collection
---@field Switch markup.Switch
---@field Array markup.Array.constructor
local core = {}

---@type markup.core
return setmetatable(core, {
	__index = function(_, k)
		return enum:lookup(k)
	end,
})
