local markup = require("markup.core")
local log = require("markup.logger") ---@diagnostic disable-line: unused-local
local u = require("markup.utils") ---@diagnostic disable-line: unused-local
local BasicObject = require("markup.core.object.basic")
local Stack = require("markup.collection.stack")

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
	else
		self.tail.next = node
	end
	self.tail = node

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

	if not self.head then
		self.tail = node
	end
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

function Line:offset()
	local text = self.head.val
	while text.head do
		text = text.head.val
	end
	local start_offset = text:offset().col_start

	text = self.tail.val
	while text.head do
		text = text.head.val
	end
	local end_offset = text:offset().col_end

	return start_offset, end_offset
end

---@param renderer markup.Renderer
---@param row_at integer (1-indexed)
function Line:paint(renderer, row_at)
	local offset = 0

	local stack = Stack.new()
	Stack.push(stack, self.head)

	while stack.len > 0 do
		local node = Stack.pop(stack)

		if node.val.head then
			Stack.push(stack, node.next)
			Stack.push(stack, node.val.head)
		else
			local text = node.val ---@type markup.Text
			local hl = text:highlight()

			local start_offset = offset
			offset = offset + text.len

			text:set_offset(row_at, start_offset, offset)

			if hl then
				renderer.buf:set_extmark(renderer.ns, row_at - 1, start_offset, {
					end_col = offset,
					hl_group = hl,
				})
			end

			Stack.push(stack, node.next)
		end
	end
end

return Line
