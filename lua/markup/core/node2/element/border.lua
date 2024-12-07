local markup = require("markup.core")
local log = require("markup.logger") ---@diagnostic disable-line: unused-local

---@class markup.Element.border : markup.Object
---@field x any
---@field chars string[]
---@field style string[]
local ElementBorder = markup.Object("markup.element.border")

function ElementBorder:iter_vertical(range)
	if self._.iter_vertical then
		return self._.iter_vertical(range)
	end

	local i = 1
	return function()
		if i > range then
			return nil
		end

		local uchar = self.chars[2]
		local dchar = self.chars[6]

		local col = i
		i = i + 1
		return col, { uchar, self.style }, { dchar, self.style }
	end
end

---@param parent markup.Element
function ElementBorder:vertical(parent)
	if not self.chars and not self._.iter_vertical then
		return
	end

	local range = parent:width() - 2
	local tmp_top, tmp_bottom = {}, {}

	local function process(info)
		if not info then
			return { "" }
		end
		if type(info) == "table" then
			return { info[1] or info[2] or self.style }
		else
			return { info, self.style }
		end
	end

	local max_b, max_t = 0, 0
	for col, top, bottom in self:iter_vertical(range) do
		tmp_top[col] = process(top)
		max_t = math.max(max_t, vim.api.nvim_strwidth(process(top)[1]))
		tmp_bottom[col] = process(bottom)
		max_b = math.max(max_b, vim.api.nvim_strwidth(process(bottom)[1]))
	end

	local top_lines, bottom_lines = {}, {}
	local function v_process(info, tbl, max)
		for c = 1, max do
			local char = vim.fn.strcharpart(info[1], vim.fn.charidx(info[1], c), 1)
			if not tbl[c] then
				tbl[c] = {}
			end
			table.insert(tbl[c], char)
		end
	end

	for i = 1, range do
		local top = tmp_top[i] or self.chars[2]
		local bottom = tmp_bottom[i] or self.chars[6]

		v_process(top, top_lines, max_t)
		v_process(bottom, bottom_lines, max_b)
	end

	for _, top_line in ipairs(top_lines) do
		parent.builder:prepend_line(markup.RendererLine():append(table.concat(top_line)))
	end

	for _, bottom_line in ipairs(bottom_lines) do
		parent.builder:append_line(markup.RendererLine():append(table.concat(bottom_line)))
	end

	self:corners(parent)
end

function ElementBorder:iter_horizontal(range)
	if self._.iter_horizontal then
		return self._.iter_horizontal(range)
	end

	local i = -1
	return function()
		local lchar, rchar = self.chars[8], self.chars[4]

		i = i + 1
		if i < range then
			return i, { lchar, self.style }, { rchar, self.style }
		end
	end
end

---@param parent markup.Element
function ElementBorder:horizontal(parent)
	if not self.chars and not self._.iter_horizontal then
		return
	end

	local function h_process(info)
		if not info then
			return
		end
		if type(info) == "table" then
			local char = info[1]
			if info[2] then
				local mock = parent:mock_element(info[2])
				return markup.Text(char, mock)
			else
				return char
			end
		else
			return info
		end
	end

	for row, left, right in self:iter_horizontal(parent:height()) do
		local pleft, pright = h_process(left), h_process(right)
		parent.builder:line(row):prepend(pleft or self.chars[8])
		parent.builder:line(row):append(pright or self.chars[4])
	end
end

function ElementBorder:iter_corners()
	if self._.iter_corners then
		return self._.iter_corners()
	end

	local i = 1
	return function()
		local char = self.chars[1]

		if i <= 4 then
			return { char, self.style }
		end
		i = i + 1
	end
end

---@param parent markup.Element
function ElementBorder:corners(parent)
	if not self.chars and not self._.iter_corners then
		return
	end

	parent.builder:line(0):prepend(self.chars[1])
	parent.builder:line(0):append(self.chars[3])
	parent.builder:line():append(self.chars[5])
	parent.builder:line():prepend(self.chars[7])
end

function ElementBorder:apply(parent)
	self:horizontal(parent)
	self:vertical(parent)
end

function ElementBorder:fill_chars()
	if not self.chars then
		return
	end

	local result = {}
	local num_values = #self.chars

	for i = 1, 8 do
		result[i] = self.chars[(i - 1) % num_values + 1]
	end

	self.chars = result
end

function ElementBorder:init(props)
	if type(props) == "string" then
		self.chars = { props }
	elseif vim.islist(props) then
		self.chars = props
	elseif props.chars then
		if type(props.chars) == "string" then
			self.chars = { props.chars }
		else
			self.chars = props.chars
		end
	end

	self._ = props

	self:fill_chars()
end

---@class markup.Element.border.props
---@field enabled boolean

return ElementBorder
