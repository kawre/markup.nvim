local markup = require("markup")
local log = require("markup.logger") ---@diagnostic disable-line: unused-local
local u = require("markup.utils") ---@diagnostic disable-line: unused-local

---@class markup.Renderer.Line.props
---@field texts markup.Text[]
---@field content string
---@field width integer
---@field length integer
---@field dirty boolean

---@class markup.Renderer.Line : markup.Object
---@field _ markup.Renderer.Line.props
local Line = markup.Object("markup.renderer.line")

function Line:init()
	self._ = {
		texts = {},
		content = "",
		width = 0,
		length = 0,
		dirty = false,
	}
end

function Line:_sync()
	if self._.dirty then
		self._.content = table.concat(vim.tbl_map(function(text)
			return text:content()
		end, self._.texts)) or ""
		self._.length = #self._.content
		self._.width = vim.api.nvim_strwidth(self._.content)

		self._.dirty = false
	end
end

---@return markup.Text[]
function Line:texts()
	return self._.texts
end

function Line:content()
	self:_sync()
	return self._.content
end

function Line:length()
	self:_sync()
	return self._.length
end

function Line:width()
	self:_sync()
	return self._.width
end

---@param content string|markup.Text|markup.Renderer.Line
---@param pos? integer
function Line:append(content, pos)
	pos = pos or #self._.texts + 1

	if type(content) == "string" then
		table.insert(self._.texts, pos, markup.Text(content))
	elseif content.type == "text" then
		---@cast content markup.Text
		table.insert(self._.texts, pos, content)
	else
		---@cast content markup.Renderer.Line
		for i, text in ipairs(content:texts()) do
			table.insert(self._.texts, pos + (i - 1), text)
		end
	end

	self._.dirty = true
	return self
end

---@param content string|markup.Text|markup.Renderer.Line
function Line:prepend(content)
	return self:append(content, 1)
end

---@param renderer markup.Renderer
---@param row_at integer
function Line:draw(renderer, row_at)
	local str = self:content()
	renderer:buf_set_lines(row_at, -1, false, { str })
	self:hightlight(row_at)
end

function Line:hightlight(row_at)
	local offset = 0
	for _, text in ipairs(self:texts()) do
		text:highlight(row_at, offset)
		offset = offset + text:length()
	end
end

---@alias markup.Renderer.Line.constructor fun(): markup.Renderer.Line

---@type markup.Renderer.Line.constructor
local MarkupLine = Line ---@diagnostic disable-line: assign-type-mismatch

return MarkupLine
