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
		self:_set_state(parent.owner, parent)
	end
end

---@param content markup.Text.content
function Text:set(content)
	content = tostring(content)
	self._.content = content
	self._.length = #content
	self._.width = vim.api.nvim_strwidth(content)
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

---@param style markup.Element.style
function Text:_normalize_style(style)
	if not style then
		return
	end

	local map = {
		["color"] = "fg",
	}

	for key, value in pairs(style) do
		if map[key] then
			style[map[key]] = value
			style[key] = nil
		end
	end

	return style
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

---@param linenr number line number (1-indexed)
---@param byte_start number start byte position (0-indexed)
---@return nil
function Text:highlight(linenr, byte_start)
	if not self.parent then
		return
	end

	local style = self:_normalize_style(self.parent.style)
	local hl = theme.create_dynamic_hl(style)

	if hl then
		self.owner:buf_set_extmark(nil, linenr, byte_start, {
			end_col = byte_start + self:length(),
			hl_group = hl --[[@as string]],
			hl_mode = "combine",
		})
	end
end

function Text:render()
	self.parent:_append(self) ---@diagnostic disable-line: invisible
end

---@alias markup.Text.constructor fun(content: markup.Text.content, parent?: markup.Node): markup.Text

---@type markup.Text.constructor
local MarkupText = Text ---@diagnostic disable-line: assign-type-mismatch

return MarkupText
