local log = require("markup.logger") ---@diagnostic disable-line: unused-local
local markup = require("markup.core")
local NodeType = require("markup.core.node.types").Node

---@class markup.Text : markup.Node
---@field content string
---@field len integer
---@field width integer
local Text = markup.Node:extend("markup.text")

function Text:init(content)
	Text.super.init(self, NodeType.TEXT)
	self:set(content)
end

function Text:append(value)
	self:set(self.content .. value)
end

function Text:prepend(value)
	self:set(value .. self.content)
end

function Text:remove()
	self:set("")
end

function Text:set(value)
	if not value then
		return
	end

	value = tostring(value)
	self.len = #value
	self.width = vim.api.nvim_strwidth(value)
	self.content = value
end

return Text
