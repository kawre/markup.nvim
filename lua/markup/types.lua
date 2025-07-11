---@diagnostic disable-next-line: duplicate-doc-alias
---@alias markup2
---| markup.Lookup
---| markup.Lookup.Node.Text
---| markup.Lookup.Node.Inline
---| markup.Lookup.Node.Block
---| markup.Lookup.Node.Flex
---| markup.Lookup.Node.Grid
---| markup.Lookup.Create
---| markup.Lookup.Collection
---| markup.Lookup.Hook

---@class markup.elements

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

---@class markup.Lookup.Collection
---@field Array markup.Array.constructor
---@field Switch markup.Switch

---@class markup.Lookup.Node.Text
---@field Text markup.create_element_from_text
---@field Pad markup.create_element_from_text

---@class markup.Lookup.Node.Flex
---@field Flex markup.create_element_from_element
---@field Box markup.create_element_from_element
---@field HFlex markup.create_element_from_element

---@class markup.Lookup.Node.Grid
---@field Grid markup.create_element_from_element

---@class markup.Lookup.Node.Block
---@field Block markup.create_element_from_element
---@field List markup.create_element_from_element
---@field OList markup.create_element_from_element
---@field ListItem markup.create_element_from_element
---@field Pre markup.create_element_from_element

---@class markup.Lookup.Node.Inline
---@field Inline markup.create_element_from_element
---@field Anchor markup.create_element_from_element
---@field Code markup.create_element_from_element
---@field Italic markup.create_element_from_element
---@field Mark markup.create_element_from_element
---@field Strike markup.create_element_from_element
---@field Strong markup.create_element_from_element
---@field Sub markup.create_element_from_element
---@field Sup markup.create_element_from_element
---@field Underline markup.create_element_from_element
