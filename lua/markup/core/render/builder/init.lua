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
	assert(row_at > 0, "row_at must be greater than 0")

	for i = math.max(1, self.len), row_at do
		if not self.lines[i] then
			self.lines[i] = RenderLine()
		end
	end

	self.len = math.max(self.len, row_at)
	return self.lines[row_at]
end

---@param content any
---@param row_at? integer (1-indexed)
function Builder:append(content, row_at)
	self:line(row_at):append(content)
	return self
end

function Builder:height()
	return self.len
end

function Builder:width()
	local max_len, max = 0, math.max
	for i = 1, self.len do
		max_len = max(max_len, self:line(i):text().width)
	end
	return max_len
end

return Builder
