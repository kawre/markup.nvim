local log = require("markup.logger")

---@class markup.Component.Class
---@field state table
---@field props table
---@field private _element markup.Node
local ComponentClass = {}
ComponentClass.__index = ComponentClass

function ComponentClass:init(props)
	self.state = {}
	self.props = props
	self:constructor()
end

function ComponentClass:constructor() end

---@private
function ComponentClass:re_render()
	self._element.owner:render()
end

---@return markup.Node
function ComponentClass:render()
	error("Component:render() must be implemented")
end

---@param name string
---@param default any
function ComponentClass:use_state(name, default)
	if self.state[name] == nil then
		self.state[name] = default
	end

	local setter = function(value)
		self:set_state(function(state)
			state[name] = value
		end)
	end

	return self.state[name], setter
end

---@param state table|fun(state: table)
function ComponentClass:set_state(state)
	if type(state) == "function" then
		state(self.state)
	else
		self.state = vim.tbl_deep_extend("force", self.state, state)
	end

	self:re_render()
end

return ComponentClass
