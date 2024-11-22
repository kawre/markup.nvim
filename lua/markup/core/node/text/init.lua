local markup = require("markup")
local theme = require("markup.theme")
local log = require("markup.logger") ---@diagnostic disable-line: unused-local

---@class markup.Text.props : markup.Node.props
---@field content string
---@field width integer
---@field length integer
---@field pos? table

---@class markup.Text : markup.Node
---@field protected _ markup.Text.props
---@field protected super markup.Node
local Text = markup.Node:extend("MarkupText") ---@diagnostic disable-line: undefined-field

---@param content markup.Text.content
function Text:init(content, parent)
	Text.super.init(self, {
		type = "text",
	})

	self:set(content)
	if parent then
		self:set_state(parent.owner, parent)
	end
end

---@param content markup.Text.content
function Text:set(content)
	content = tostring(content)
	self._.content = content
	self._.length = #content
	self._.width = vim.api.nvim_strwidth(content)
end

function Text:split_at_newl()
	local parts = {}

	for part in vim.gsplit(self:content(), "\n") do
		table.insert(parts, part)
	end

	return vim.tbl_map(function(part)
		return Text(part, self.parent)
	end, parts)
end

---@return string
function Text:content()
	return self._.content
end

---@return integer
function Text:length()
	return self._.length
end

---@return integer
function Text:width()
	return self._.width
end

function Text:_normalize_style()
	if not self.parent then
		return
	end

	local style = self.parent.style
	local map = {
		["color"] = "fg",
	}

	for key, value in pairs(map) do
		if style[key] then
			style[value] = style[key]
			style[key] = nil
		end
	end

	return style
end

---@return string?
function Text:highlight()
	return theme.create_dynamic_hl(self.style)
end

function Text:_set_position(row, col_start, col_end)
	self._.pos = {
		row = row,
		col_start = col_start,
		col_end = col_end,
	}
end

function Text:_get_position()
	return self._.pos
end

function Text:render()
	self.style = self:_normalize_style()
end

---@alias markup.Text.constructor fun(content: markup.Text.content, parent?: markup.Node): markup.Text

---@type markup.Text.constructor
local MarkupText = Text ---@diagnostic disable-line: assign-type-mismatch

return MarkupText
