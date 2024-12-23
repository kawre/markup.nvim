local BasicObject = require("markup.core.object.basic")
local log = require("markup.logger") ---@diagnostic disable-line: unused-local

---@class markup.Window.win
---@field window markup.Window
---@field [string] function
local Win = BasicObject()

Win.__index = function(_, key)
	if Win[key] then
		return Win[key]
	end

	return function(self, ...)
		local id = self.window.id
		assert(id, "Window is not valid")
		return id and vim.api["nvim_win_" .. key](id, ...)
	end
end

function Win:id()
	return self.window.id
end

function Win:is_valid()
	return self:id() and vim.api.nvim_win_is_valid(self:id())
end

---@param window markup.Window
function Win:init(window)
	self.window = window
end

function Win:close()
	if self:is_valid() then
		vim.api.nvim_win_close(self:id(), true)
	end
	self.window.id = nil
end

---@param name string
function Win:get_option_value(name)
	assert(self.win:is_valid(), "Window is not valid")
	return vim.api.nvim_get_option_value(name, { win = self:id(), scope = "local" })
end

---@param name string
---@param value any
function Win:set_option_value(name, value)
	assert(self.win:is_valid(), "Window is not valid")
	vim.api.nvim_set_option_value(name, value, { win = self:id(), scope = "local" })
end

return Win
