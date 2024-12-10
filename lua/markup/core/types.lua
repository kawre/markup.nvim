---@diagnostic disable-next-line: duplicate-doc-alias
---@alias markup.core
---| { Render: markup.core.Lookup.Render }
---| markup.core.Lookup
---| markup.core.Lookup.Node.Text
---| markup.core.Lookup.Node.Inline
---| markup.core.Lookup.Node.Block
---| markup.core.Lookup.Node.Flex
---| markup.core.Lookup.Renderer
---| markup.core.Lookup.Render
---| markup.core.Lookup.Create
---| markup.core.Lookup.Collection

---@class markup.core.Lookup
---@field Fiber markup.Fiber
---@field Parser markup.Parser.constructor
---@field Object markup.Object.constructor
---@field Window markup.Window.constructor
---@field Reconciler markup.Reconciler.constructor
---@field TabPage markup.TabPage.constructor

---@class markup.core.Lookup.Node.Text
---@field Text markup.Text.constructor
---@field Pad markup.Padding.constructor

---@class markup.core.Lookup.Node.Flex
---@field Flex markup.Flex.constructor
---@field Box markup.Flex.constructor
---@field HFlex markup.Flex.Horizontal.constructor

---@class markup.core.Lookup.Node.Grid
---@field Grid markup.Grid.constructor

---@class markup.core.Lookup.Node.Block
---@field Block markup.Block.constructor
---@field List markup.List.constructor
---@field OList markup.List.constructor
---@field ListItem markup.Block.constructor
---@field Pre markup.Pre.constructor

---@class markup.core.Lookup.Node.Inline
---@field Inline markup.Inline.constructor
---@field Anchor markup.Anchor.constructor
---@field Code markup.Code.constructor
---@field Italic markup.Italic.constructor
---@field Mark markup.Mark.constructor
---@field Strike markup.Strike.constructor
---@field Strong markup.Strong.constructor
---@field Sub markup.Sub.constructor
---@field Sup markup.Sup.constructor
---@field Underline markup.Underline.constructor

---@class markup.core.Lookup.Renderer
---@field Renderer markup.Renderer.constructor
---@field RendererLine markup.Renderer.Line.constructor
---@field RendererBuilder markup.Renderer.Builder

---@class markup.core.Lookup.Render
---@field Tree markup.Render.Tree
---@field View markup.Render.View
---@field Object markup.Render.Object
---@field Box markup.Render.Box
---@field Flow markup.Render.Flow
---@field Inline markup.Render.Inline
---@field Block markup.Render.Block
---@field Flex markup.Render.Flex

---@class markup.core.Lookup.Create
---@field create_element markup.create_element
---@field create_component markup.create_component
---@field create_root markup.create_root
---@field create_fiber markup.create_fiber
---@field create_fiber_root markup.create_fiber_root
---@field create_fiber_from_element markup.create_fiber_from_element
---@field create_fiber_from_text markup.create_fiber_from_text
---@field create_fiber_from_fragment markup.create_fiber_from_text
---@field create_renderer_root markup.create_renderer_root

---@class markup.core.Lookup.Collection
---@field Array markup.Array.constructor
---@field Switch markup.Switch
---@field Enum markup.Enum
