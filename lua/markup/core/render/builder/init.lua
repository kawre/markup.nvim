local log = require("markup.logger") ---@diagnostic disable-line: unused-local
local RenderLine = require("markup.core.render.builder.line")
local BasicObject = require("markup.core.object.basic")

---@class markup.Render.Builder
---@field row integer
---@field lines markup.Render.Line[]
local Builder = BasicObject()

function Builder:init()
	self.lines = {}
	self.row = 1
	self.len = 0
end

---@param n? integer
---@return markup.Render.Builder
function Builder:newl(n)
	self.row = self.row + (n or 1)
	return self
end

function Builder:reset()
	self.lines = {}
	self.row = 1
	self.len = 0
end

---@param row_at? integer (1-indexed)
---@return markup.Render.Line
function Builder:line(row_at)
	row_at = row_at or self.row
	return self:_line(row_at)
end

function Builder:_line(row_at)
	self.len = math.max(self.len, row_at)
	self:fill(row_at)
	return self.lines[row_at]
end

---@param row_at? integer (1-indexed)
function Builder:fill(row_at)
	for i = self.len, row_at or self.row do
		if not self.lines[i] then
			self.lines[i] = RenderLine()
		end
	end
end

function Builder:height()
	return self.len
end

function Builder:width()
	local max_len, max = 0, math.max
	for i = 1, self.len do
		max_len = max(max_len, self.lines[i]:text().width)
	end
	return max_len
end

return Builder
