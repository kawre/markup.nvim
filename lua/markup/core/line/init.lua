local markup = require("markup")
local log = require("markup.logger")

---@class markup.Line.props
---@field chars string[]
---@field highlights { col_start: integer, col_end: integer, hl_group: string }[]

---@class markup.Line : markup.Object
local Line = markup.Object("MarkupLine")

function Line:init()
	self._ = {
		chars = {},
		highlights = {},
	}
end

function Line:content()
	return table.concat(self._.chars)
end

function Line:length()
	return #self._.chars
end

function Line:width()
	return vim.api.nvim_strwidth(self:content())
end

function Line:draw(renderer, row_at)
	local str = self:content()
	vim.api.nvim_buf_set_lines(renderer._.bufnr, row_at, -1, true, { str })

	-- local offset = 0
	-- for _, text in ipairs(self._.highlights) do
	-- text:highlight(renderer._.bufnr, renderer._.ns_id, row_at, offset)
	-- offset = offset + text:width()
	-- end
end

---@param text markup.Text
function Line:append(text, col_at)
	col_at = col_at or #self._.chars
	local str = text:content()

	if col_at > #self._.chars then
		for _ = #self._.chars, col_at do
			table.insert(self._.chars, " ")
		end
	end

	for i = 1, #str do
		table.insert(self._.chars, col_at + i, str:sub(i, i))
	end

	return self
end

---@alias markup.Line.constructor fun(): markup.Line

---@type markup.Line.constructor
local MarkupLine = Line

return MarkupLine
