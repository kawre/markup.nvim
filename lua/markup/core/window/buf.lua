local BasicObject = require("markup.core.object.basic")
local log = require("markup.logger") ---@diagnostic disable-line: unused-local

---@class markup.Window.buf
---@field window markup.Window
---@field [string] function
local Buf = BasicObject()

Buf.__index = function(self, key)
	if Buf[key] then
		return Buf[key]
	end

	return function(_, ...)
		local bufnr = self.window.bufnr
		assert(bufnr, "Buffer is not valid")
		return bufnr and vim.api["nvim_buf_" .. key](bufnr, ...)
	end
end

---@param window markup.Window
function Buf:init(window)
	self.window = window
end

function Buf:nr()
	return self.window.bufnr
end

function Buf:is_valid()
	return self:nr() and vim.api.nvim_buf_is_valid(self:nr())
end

function Buf:open()
	if not self:nr() or not self:is_valid() then
		self.window.bufnr = vim.api.nvim_create_buf(false, true)
	end

	return self:nr()
end

---@param name string
function Buf:get_option_value(name)
	return vim.api.nvim_get_option_value(name, { buf = self:nr() })
end

---@param name string
---@param value any
function Buf:set_option_value(name, value)
	vim.api.nvim_set_option_value(name, value, { buf = self:nr() })
end

return Buf
