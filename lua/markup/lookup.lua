local ElementFactory = require("markup.core.factory.element")

---@alias markup.Element.constructor fun(props: any, style: any): markup.Element

---@class markup.lookup
local M = {}

-----------------------------------------------
-- Primitives
-----------------------------------------------

setmetatable(M, {
	__index = function(_, key)
		return function(...)
			return ElementFactory.create(key:lower(), ...)
		end
	end,
})
M.element = ElementFactory.create

-----------------------------------------------
-- Complex Element Creation
-----------------------------------------------

M.Component = ElementFactory.create_component
M.Class = ElementFactory.create_class
M.Fragment = ElementFactory.create_fragment

-----------------------------------------------
-- User Interface
-----------------------------------------------

M.Renderer = require("markup.core.window.renderer")
M.Window = require("markup.core.window")
M.Tabpage = require("markup.core.tabpage")

return M
