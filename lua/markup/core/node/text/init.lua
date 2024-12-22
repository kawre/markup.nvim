local markup = require("markup.core")

local theme = require("markup.theme")
local log = require("markup.logger") ---@diagnostic disable-line: unused-local
local NodeType = require("markup.core.node.enum").Type

---@class markup.Text : markup.Node
---@field content string
---@field len integer
---@field width integer
local Text = markup.Node:extend("MarkupText")
Text.__type = "text"

---@class markup.Text.static : markup.Node.static
Text.static = Text.static

function Text:__tostring()
	return self.content
end

function Text:init(content)
	Text.super.init(self, NodeType.TEXT)
	self:set(content)
end

function Text:is_text()
	return true
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

---@return string?
function Text:highlight()
	return theme.create_dynamic_hl(self.props.style or {})
end

---@alias markup.Text.constructor
---| fun(content: string | number): markup.Text
---| { static: markup.Text.static }
---| markup.Text.static

---@type markup.Text.constructor
return Text
