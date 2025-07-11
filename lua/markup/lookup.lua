local ElementFactory = require("markup.core.factory.element")

---@class markup.lookup
local M = {}

-----------------------------------------------
-- Element Creation
-----------------------------------------------

M.Inline = function(...)
	return ElementFactory.create("inline", ...)
end
M.Block = function(...)
	return ElementFactory.create("block", ...)
end
M.Flex = function(...)
	return ElementFactory.create("flex", ...)
end
M.Element = function(...)
	return ElementFactory.create(...)
end
M.Component = ElementFactory.create_component
M.Fragment = ElementFactory.create_fragment

-----------------------------------------------
-- User Interface
-----------------------------------------------

M.Renderer = require("markup.core.window.renderer")
M.Window = require("markup.core.window")
M.Tabpage = require("markup.core.tabpage")

return M
