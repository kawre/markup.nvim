local markup = require("markup.core")

---@class markup.Renderer.Builder : markup.Object
---@field row integer
---@field lines markup.Renderer.Line[]
local Builder = markup.Object("markup.renderer.line.builder")

function Builder:init()
	self.lines = {}
	self.row = 0
end

---@param n? integer
---@return markup.Renderer.Builder
function Builder:newl(n)
	self:inc_row(n or 1)
	self:fill()
	return self
end

function Builder:reset()
	self.row = 0
	self.lines = {}
end

---@param row_at? integer (0-indexed)
---@return markup.Renderer.Line
function Builder:line(row_at)
	row_at = row_at or self.row
	self:fill(row_at)
	return self.lines[row_at]
end

---@param row_at? integer (0-indexed)
function Builder:fill(row_at)
	local lines = self.lines
	for i = #lines, row_at or self.row do
		if not lines[i] then
			lines[i] = markup.RendererLine()
		end
	end
end

---@param n integer
function Builder:inc_row(n)
	self.row = self.row + n
	return self.row
end

---@param content string|markup.Text|markup.Renderer.Line
---@param row_at? integer (0-indexed)
---@return markup.Renderer.Builder
function Builder:append(content, row_at)
	self:line(row_at):append(content)
	return self
end

---@param line markup.Renderer.Line
---@param row_at? integer
function Builder:append_line(line, row_at)
	if row_at then
		table.insert(self.lines, row_at, line)
	else
		table.insert(self.lines, line)
	end
	self:inc_row(1)
	return self
end

---@param line markup.Renderer.Line
function Builder:prepend_line(line)
	return self:append_line(line, 0)
end

function Builder:height()
	return vim.tbl_count(self.lines)
end

function Builder:width()
	local max_len = 0
	for _, line in pairs(self.lines) do
		max_len = math.max(max_len, line:width())
	end
	return max_len
end

---@param content string|markup.Text|markup.Renderer.Line
---@param row_at? integer (0-indexed)
---@return markup.Renderer.Builder
function Builder:prepend(content, row_at)
	self:line(row_at):prepend(content)
	return self
end

return Builder
