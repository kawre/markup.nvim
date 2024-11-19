local log = require("markup.logger")

---@class markup.Component.Class
---@field state? table
---@field props? table
---@field _element? markup.Node
local ComponentClass = {}
ComponentClass.__index = ComponentClass

function ComponentClass:init()
	self.state = {}
	self.props = {}
	self:constructor()
end

function ComponentClass:constructor() end

function ComponentClass:re_render()
	self._element.owner:render()
end

---@return markup.Node
function ComponentClass:render()
	log.error("ComponentClass:render() must be implemented")
end

function ComponentClass:set_state(state)
	self.state = vim.tbl_deep_extend("force", self.state, state)
	self:re_render()
end

return ComponentClass
