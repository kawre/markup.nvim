local markup = require("markup.core")
local log = require("markup.logger") ---@diagnostic disable-line: unused-local
local u = require("markup.utils") ---@diagnostic disable-line: unused-local
local BasicObject = require("markup.core.object.basic")

---@class markup.Render.Line.node
---@field val markup.Text | markup.Render.Line
---@field next markup.Render.Line.node

---@class markup.Render.Line.text
---@field content string
---@field width integer
---@field len integer

---@class markup.Render.Line : markup.Object
---@field protected _text markup.Render.Line.text
---@field _texts markup.Text[]
---@field head markup.Render.Line.node
---@field tail markup.Render.Line.node
---@field dirty boolean
local Line = BasicObject()

function Line:init()
	self._texts = {}
	self._text = {
		content = "",
		width = 0,
		len = 0,
	}

	self.head = nil
	self.tail = nil
	self._len = 0

	self.dirty = false
end

function Line:__tostring()
	local tbl, len = {}, 0

	local node = self.head
	while node do
		len = len + 1
		tbl[len] = tostring(node.val)
		node = node.next
	end

	return table.concat(tbl)
end

function Line:text()
	if self.dirty then
		self._text.content = tostring(self)
		self._text.len = #self._text.content
		self._text.width = vim.api.nvim_strwidth(self._text.content)

		self.dirty = false
	end

	return self._text
end

local function normalize_content(content)
	if type(content) == "string" then
		return markup.Text(content)
	else
		return content
	end
end

---@param content string|markup.Text|markup.Render.Line
function Line:append(content)
	self._len = self._len + 1

	local node = {
		val = normalize_content(content),
		next = nil,
	}

	if not self.tail then
		self.head = node
		self.tail = node
	else
		self.tail.next = node
		self.tail = node
	end

	self.dirty = true
	return self
end

---@param content string|markup.Text|markup.Render.Line
function Line:prepend(content)
	self._len = self._len + 1

	local node = {
		val = normalize_content(content),
		next = self.head,
	}

	self.head = node

	self.dirty = true
	return self
end

function Line:content()
	return self:text().content
end

function Line:len()
	return self:text().len
end

function Line:width()
	return self:text().width
end

---@param renderer markup.Renderer
---@param row_at integer (1-indexed)
function Line:paint(renderer, row_at)
	local offset, i = 0, 1

	-- local node = self.head
	-- while node do
	-- end
	-- while texts[i] do
	-- 	local start_offset = offset
	-- 	local hl = texts[i]:highlight()
	--
	-- 	local j = i
	-- 	while texts[j] and texts[j]:highlight() == hl do
	-- 		local old_offset = offset
	-- 		offset = offset + texts[j].len
	-- 		-- texts[j]:_set_position(row_at, old_offset, offset)
	-- 		j = j + 1
	-- 	end
	--
	-- 	if hl then
	-- 		renderer.buf:set_extmark(nil, row_at, start_offset, {
	-- 			end_col = offset,
	-- 			hl_group = hl,
	-- 		})
	-- 	end
	--
	-- 	i = j
	-- end
end

return Line
