local markup = require("markup.core")
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
			---@type markup.Text
			return text.content
		end, self._.texts)) or ""
		self._.length = #self._.content
		-- self._.width = vim.api.nvim_strwidth(self._.content)

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
	renderer:buf_set_lines(row_at, -1, false, { self:content() })
end

---@param renderer markup.Renderer
---@param row_at integer
function Line:paint(renderer, row_at)
	local offset, i, texts = 0, 1, self:texts()

	while texts[i] do
		local start_offset = offset
		local hl = texts[i]:highlight()

		local j = i
		while texts[j] and texts[j]:highlight() == hl do
			local old_offset = offset
			offset = offset + texts[j].len
			-- texts[j]:_set_position(row_at, old_offset, offset)
			j = j + 1
		end

		if hl then
			renderer:buf_set_extmark(nil, row_at, start_offset, {
				end_col = offset,
				hl_group = hl,
			})
		end

		i = j
	end
end

---@alias markup.Renderer.Line.constructor fun(): markup.Renderer.Line

---@type markup.Renderer.Line.constructor
local MarkupLine = Line ---@diagnostic disable-line: assign-type-mismatch

return MarkupLine
