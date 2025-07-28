---@class markup.renderer.line
---@field dirty boolean
local M = Markup.object()

function M:new()
	self.dirty = true
	self.line = {}
	self.hl = {}
end

---@param box markup.box
function M:insert(box)
	self.line[box.wx] = box
	box.line = self
end

function M:highlight(col_start, col_end, hl)
	self.hl[#self.hl + 1] = {
		col_start = col_start,
		col_end = col_end,
		hl_group = hl,
	}
end

function M:paint(line, ns)
	for _, highlight in ipairs(self.hl) do
		local char_start = vim.fn.byteidx(self.cache, highlight.col_start)
		local char_end = vim.fn.byteidx(self.cache, highlight.col_end)

		vim.api.nvim_buf_set_extmark(0, ns, line - 1, char_start, {
			end_col = char_end,
			hl_eol = true,
			hl_group = highlight.hl_group,
			hl_mode = "combine",
		})
	end
end

local whitespace_cache = setmetatable({}, {
	__index = function(t, k)
		t[k] = (" "):rep(k)
		return rawget(t, k)
	end,
})

---@param width integer
---@return string
function M:build(width)
	local line = {}
	local cw = 0
	local dx = 0

	local keys = vim.tbl_keys(self.line)
	table.sort(keys, function(a, b)
		return a < b
	end)

	for _, x in ipairs(keys) do
		local word = self.line[x].text_content

		if x > cw then
			local spaces = x - cw
			line[#line + 1] = whitespace_cache[spaces]
			cw = cw + spaces
			dx = dx + spaces
		end

		line[#line + 1] = word
		cw = cw + self.line[x].width
		dx = dx + vim.fn.strdisplaywidth(word)
	end

	if dx < width then
		local spaces = width - dx
		line[#line + 1] = whitespace_cache[spaces]
	end

	self.cache = table.concat(line)
	return self.cache
end

return M
