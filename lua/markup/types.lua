---@diagnostic disable-next-line: duplicate-doc-alias
---@alias markup
---| { core: markup.core }
---| markup.Lookup
---| markup.Lookup.Node
---| markup.Lookup.Create
---| markup.Lookup.Collection
---| markup.Lookup.Hook

---@class markup.Lookup
---@field Parser markup.Parser.constructor
---@field Window markup.Window.constructor
---@field Renderer markup.Renderer.constructor
---@field TabPage markup.TabPage.constructor

---@class markup.Lookup.Hook
---@field useState markup.use_state
---@field use_state markup.use_state

---@class markup.Lookup.Create
---@field Element markup.create_element
---@field Component markup.create_component
---@field Fragment markup.create_fragment

---@class markup.Lookup.Node
---@field Inline markup.Inline.constructor
---@field Block markup.Block.constructor
---@field Flex markup.Flex.constructor

---@class markup.Lookup.Collection
---@field Array markup.Array.constructor
---@field Switch markup.Switch
