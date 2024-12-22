local log = require("markup.logger") ---@diagnostic disable-line: unused-local
local BasicObject = require("markup.core.object.basic")
-- local Collection = require("markup.core.enum").Collection

---@class markup.Array : tablelib
local Array = BasicObject()

Array.__index = function(_, key)
	return Array[key] or table[key]
end

function Array:init()
	self.len = 0
end

function Array:map(apply)
	return Array(vim.tbl_map(apply, self))
end

function Array:filter(fn)
	return Array(vim.tbl_filter(fn, self))
end

function Array:isempty()
	return vim.tbl_isempty(self)
end

function Array:contains(value)
	return vim.tbl_contains(self, value)
end

function Array:foreach(fn)
	for i, v in ipairs(self) do
		self[i] = fn(v, i)
	end
end

---@alias markup.Array.constructor fun(init?: table): markup.Array

---@type markup.Array.constructor
return Array
