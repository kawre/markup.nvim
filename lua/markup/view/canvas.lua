--- Direct 2D cell drawing surface for `m.canvas`.
---
--- Drawing writes into flat Lua arrays reused across frames and flushes them as
--- a single `set_canvas` command per frame, bypassing layout completely.

local ffi = require("ffi")
local hl = require("markup.view.hl")
local protocol = require("markup.view.protocol")

local floor = math.floor
local min, max = math.min, math.max
local concat = table.concat
local sub, byte = string.sub, string.byte
local clear_table = require("table.clear")

local TAB = "    "

---@class markup.view.canvas
local M = {}

---@class markup.canvas.context
---@field width integer content width in cells
---@field height integer content height in cells
local Context = {}
Context.__index = Context

--- Byte length of the UTF-8 character starting at `offset` in `text`.
---@param text string
---@param offset integer
---@return integer
local function utf8_len(text, offset)
	local b = byte(text, offset)
	if b < 0x80 then
		return 1
	elseif b >= 0xC2 and b <= 0xDF then
		return 2
	elseif b >= 0xE0 and b <= 0xEF then
		return 3
	elseif b >= 0xF0 and b <= 0xF4 then
		return 4
	end
	return 1
end

--- The highlight id of a style. A table is looked up by identity: interning
--- one serializes it, which a draw doing it per cell cannot afford. The cache
--- lasts one draw, so a table changed between frames is seen again.
---@param self markup.canvas.context
---@param style? markup.factory.element.style
---@return integer
local function style_id(self, style)
	if style == nil then
		return 0
	end
	if type(style) ~= "table" then
		return hl.id(style)
	end
	local cache = self._style_ids
	local id = cache[style]
	if not id then
		id = hl.id(style)
		cache[style] = id
	end
	return id
end

--- Clears the partner cell of any wide character occupying `index`.
local function detach_wide(chars, widths, index)
	local w = widths[index]
	if w == 0 then
		chars[index - 1] = " "
		widths[index - 1] = 1
	elseif w == 2 then
		chars[index + 1] = " "
		widths[index + 1] = 1
	end
end

--- Writes a single character of known width `cw` (1 or 2) at 0-indexed `(x, y)`.
local function put_cell(self, x, y, char, cw, hl_id)
	local w = self.width
	local i = y * w + x + 1
	local chars, widths, hls = self.chars, self.widths, self.hls

	detach_wide(chars, widths, i)

	if cw == 2 then
		if x + 1 >= w then
			-- A wide character on the right edge cannot be halved: leave a blank.
			chars[i] = " "
			widths[i] = 1
			hls[i] = hl_id
			return
		end
		if widths[i + 1] == 2 then
			chars[i + 2] = " "
			widths[i + 2] = 1
		end
		chars[i], widths[i], hls[i] = char, 2, hl_id
		chars[i + 1], widths[i + 1], hls[i + 1] = "", 0, hl_id
		self.row_non_unit[y + 1] = true
	else
		chars[i], widths[i], hls[i] = char, 1, hl_id
	end
end

--- Resizes the backing grid, resetting all cells when the dimensions change.
---@param width integer
---@param height integer
function Context:resize(width, height)
	width = max(floor(width), 0)
	height = max(floor(height), 0)
	if self.width == width and self.height == height then
		return
	end
	self.width = width
	self.height = height
	self.chars = {}
	self.widths = {}
	self.hls = {}
	self.row_non_unit = {}
	self:clear()
end

--- Fills the whole canvas with `char` (a blank by default) and optional `style`.
---@param char? string
---@param style? markup.factory.element.style
function Context:clear(char, style)
	local total = self.width * self.height
	local chars, widths, hls = self.chars, self.widths, self.hls
	local non_unit = self.row_non_unit

	if char == nil and style == nil then
		for i = 1, total do
			chars[i], widths[i], hls[i] = " ", 1, 0
		end
		for row = 1, self.height do
			non_unit[row] = false
		end
		return
	end

	local fill_char = char or " "
	local hl_id = style_id(self, style)
	if #fill_char == 1 and byte(fill_char, 1) < 128 then
		for i = 1, total do
			chars[i], widths[i], hls[i] = fill_char, 1, hl_id
		end
		for row = 1, self.height do
			non_unit[row] = false
		end
		return
	end

	self:clear()
	self:fill(0, 0, self.width, self.height, fill_char, style)
end

--- Draws one character at zero-indexed `(x, y)`. With `char == nil`, keeps the
--- character already there and only sets its highlight.
---@param x integer
---@param y integer
---@param char? string
---@param style? markup.factory.element.style
function Context:set(x, y, char, style)
	x, y = floor(x), floor(y)
	local w, h = self.width, self.height
	if x < 0 or x >= w or y < 0 or y >= h then
		return
	end

	local hl_id = style_id(self, style)
	if char == nil then
		local i = y * w + x + 1
		local cell_w = self.widths[i]
		self.hls[i] = hl_id
		if cell_w == 2 then
			self.hls[i + 1] = hl_id
		elseif cell_w == 0 then
			self.hls[i - 1] = hl_id
		end
		return
	end

	if char == "" then
		return
	end

	local len = #char
	if len == 1 and byte(char, 1) < 128 then
		put_cell(self, x, y, char, 1, hl_id)
		return
	end

	if len == utf8_len(char, 1) then
		local cw = protocol.char_width(char)
		if cw > 0 then
			put_cell(self, x, y, char, cw, hl_id)
		end
		return
	end

	self:text(x, y, char, style)
end

--- Writes a single line of text at `(x, y)` with an already-interned highlight id.
local function draw_line(self, x, y, line, hl_id)
	local w = self.width
	if y < 0 or y >= self.height or x >= w or #line == 0 then
		return
	end

	if not line:find("[\128-\255]") then
		local first = max(1, 1 - x)
		local last = min(#line, w - x)
		if first > last then
			return
		end
		local chars, widths, hls = self.chars, self.widths, self.hls
		local base = y * w + x
		for k = first, last do
			local i = base + k
			detach_wide(chars, widths, i)
			chars[i], widths[i], hls[i] = sub(line, k, k), 1, hl_id
		end
		return
	end

	line = protocol.valid_utf8(line)
	local col, at, length = x, 1, #line
	local last_cell
	while at <= length do
		local size = utf8_len(line, at)
		local ch = sub(line, at, at + size - 1)
		at = at + size

		local cw = protocol.char_width(ch)
		if cw == 0 then
			if last_cell then
				self.chars[last_cell] = self.chars[last_cell] .. ch
				self.row_non_unit[y + 1] = true
			end
		else
			last_cell = nil
			if col + cw <= 0 then
				col = col + cw
			elseif col < 0 then
				-- Wide character straddling the left edge leaves its right half blank.
				put_cell(self, 0, y, " ", 1, hl_id)
				col = col + cw
			elseif col >= w then
				break
			else
				put_cell(self, col, y, ch, cw, hl_id)
				if cw == 1 or col + 1 < w then
					last_cell = y * w + col + 1
				end
				col = col + cw
			end
		end
	end
end

--- Draws `text` starting at zero-indexed `(x, y)`. Newlines advance to the next
--- row at the same `x`, and anything outside the canvas is clipped cleanly.
---@param x integer
---@param y integer
---@param text string|number
---@param style? markup.factory.element.style
function Context:text(x, y, text, style)
	text = tostring(text)
	if #text == 0 then
		return
	end
	if text:find("\t", 1, true) then
		text = text:gsub("\t", TAB)
	end

	x, y = floor(x), floor(y)
	local hl_id = style_id(self, style)
	if not text:find("\n", 1, true) then
		draw_line(self, x, y, text, hl_id)
		return
	end

	local row = y
	for line in (text .. "\n"):gmatch("([^\n]*)\n") do
		if row >= self.height then
			break
		end
		draw_line(self, x, row, line, hl_id)
		row = row + 1
	end
end

--- Fills a rectangle at `(x, y)` of size `width` × `height` with `char` (blank
--- by default) and optional `style`.
---@param x integer
---@param y integer
---@param width integer
---@param height integer
---@param char? string
---@param style? markup.factory.element.style
function Context:fill(x, y, width, height, char, style)
	x, y, width, height = floor(x), floor(y), floor(width), floor(height)
	local x0, y0 = max(x, 0), max(y, 0)
	local x1, y1 = min(x + width, self.width), min(y + height, self.height)
	if x0 >= x1 or y0 >= y1 then
		return
	end

	local hl_id = style_id(self, style)
	if char == nil then
		local fill_char = " "
		local chars, widths, hls = self.chars, self.widths, self.hls
		local w = self.width
		for row = y0, y1 - 1 do
			local base = row * w + 1
			for col = x0, x1 - 1 do
				local i = base + col
				detach_wide(chars, widths, i)
				chars[i], widths[i], hls[i] = fill_char, 1, hl_id
			end
		end
		return
	end

	if char == "" then
		return
	end

	local cw = #char == 1 and byte(char, 1) < 128 and 1 or protocol.char_width(char)
	if cw <= 0 then
		return
	end
	for row = y0, y1 - 1 do
		local col = x0
		while col < x1 do
			if cw == 2 and col + 1 >= x1 then
				put_cell(self, col, row, " ", 1, hl_id)
				break
			end
			put_cell(self, col, row, char, cw, hl_id)
			col = col + cw
		end
	end
end

--- Draws a line from `(x0, y0)` to `(x1, y1)` using Bresenham's algorithm.
---@param x0 integer
---@param y0 integer
---@param x1 integer
---@param y1 integer
---@param char? string
---@param style? markup.factory.element.style
function Context:line(x0, y0, x1, y1, char, style)
	x0, y0, x1, y1 = floor(x0), floor(y0), floor(x1), floor(y1)
	local glyph = char or "█"
	local hl_id = style_id(self, style)
	local cw = #glyph == 1 and byte(glyph, 1) < 128 and 1 or protocol.char_width(glyph)
	if cw <= 0 then
		return
	end

	local dx = math.abs(x1 - x0)
	local sx = x0 < x1 and 1 or -1
	local dy = -math.abs(y1 - y0)
	local sy = y0 < y1 and 1 or -1
	local err = dx + dy
	local w, h = self.width, self.height

	while true do
		if x0 >= 0 and x0 < w and y0 >= 0 and y0 < h then
			put_cell(self, x0, y0, glyph, cw, hl_id)
		end
		if x0 == x1 and y0 == y1 then
			break
		end
		local e2 = 2 * err
		if e2 >= dy then
			err = err + dy
			x0 = x0 + sx
		end
		if e2 <= dx then
			err = err + dx
			y0 = y0 + sy
		end
	end
end

--- Splits an 8-character border string into its corners and edges.
local function border_chars(border)
	local preset = type(border) == "table" and border.chars
		or (protocol.borders[border or "single"] or {}).chars
		or border
	local chars = {}
	if type(preset) == "string" then
		local at, length = 1, #preset
		while at <= length do
			local size = utf8_len(preset, at)
			chars[#chars + 1] = sub(preset, at, at + size - 1)
			at = at + size
		end
	end
	if #chars ~= 8 then
		error(("invalid border `%s`"):format(tostring(border)), 0)
	end
	return chars
end

--- Draws an outlined rectangle at `(x, y)` of size `width` × `height`.
---@param x integer
---@param y integer
---@param width integer
---@param height integer
---@param border? markup.border|string preset name or 8-character border string
---@param style? markup.factory.element.style
function Context:rect(x, y, width, height, border, style)
	x, y, width, height = floor(x), floor(y), floor(width), floor(height)
	if width <= 0 or height <= 0 then
		return
	end

	local b = border_chars(border)
	local hl_id = style_id(self, style)
	local x1, y1 = x + width - 1, y + height - 1
	local cw_w, cw_h = self.width, self.height

	local function plot(px, py, ch)
		if px >= 0 and px < cw_w and py >= 0 and py < cw_h then
			put_cell(self, px, py, ch, 1, hl_id)
		end
	end

	if height == 1 then
		for col = x, x1 do
			plot(col, y, b[2])
		end
		return
	end
	if width == 1 then
		for row = y, y1 do
			plot(x, row, b[4])
		end
		return
	end

	plot(x, y, b[1])
	plot(x1, y, b[3])
	plot(x, y1, b[7])
	plot(x1, y1, b[5])

	for col = x + 1, x1 - 1 do
		plot(col, y, b[2])
		plot(col, y1, b[6])
	end
	for row = y + 1, y1 - 1 do
		plot(x, row, b[8])
		plot(x1, row, b[4])
	end
end

--- Forgets the styles of the last draw, before the next one.
function Context:begin()
	clear_table(self._style_ids)
end

--- Whether the cell at `i` was drawn: anything but a blank with no style.
local function drawn(chars, hls, i)
	return chars[i] ~= " " or hls[i] ~= 0
end

--- Adds the cells `first..last` of a row (1-indexed, from `base`) as the
--- `k + 1`th run, returning `k + 1`.
local function add_run(self, runs, k, row, base, first, last)
	local chars, widths, scratch = self.chars, self.widths, self._scratch
	local n = 0
	for col = first, last do
		local i = base + col
		if widths[i] ~= 0 then
			n = n + 1
			scratch[n] = chars[i]
		end
	end
	local text = concat(scratch, "", 1, n)
	k = k + 1
	runs.starts[k], runs.texts[k], runs.widths[k] = first - 1, text, last - first + 1
	runs.cells[k] = self.row_non_unit[row] and protocol.cell_digits(text) or ""
	runs.count[row] = runs.count[row] + 1
	return k
end

--- Packs the canvas surface into a single `set_canvas` engine command. An
--- opaque canvas sends each row as one run from its left edge; a transparent
--- one sends only the runs of cells it drew, so the rest shows through.
---@param commands markup.view.commands
---@param id integer
function Context:flush(commands, id)
	local w, h = self.width, self.height
	local transparent = self.transparent and 1 or 0
	local runs = self._runs
	if w == 0 or h == 0 then
		commands:set_canvas(id, w, h, transparent, 0, runs)
		return
	end

	local chars, hls = self.chars, self.hls
	local row_runs, ranges = runs.count, runs.ranges
	local u32 = self._u32
	if self._u32_cap < w * 3 then
		self._u32_cap = w * 3
		u32 = ffi.new("uint32_t[?]", self._u32_cap)
		self._u32 = u32
	end

	local k = 0
	for row = 1, h do
		local base = (row - 1) * w
		local last = 0
		for col = w, 1, -1 do
			if drawn(chars, hls, base + col) then
				last = col
				break
			end
		end

		row_runs[row] = 0
		if last == 0 then
			ranges[row] = ""
		else
			if transparent == 0 then
				k = add_run(self, runs, k, row, base, 1, last)
			else
				local first
				for col = 1, last + 1 do
					if col <= last and drawn(chars, hls, base + col) then
						first = first or col
					elseif first then
						k = add_run(self, runs, k, row, base, first, col - 1)
						first = nil
					end
				end
			end

			local r_len = 0
			local cur_hl, cur_start = 0, 0
			for col = 1, last do
				local cell_hl = hls[base + col]
				if cell_hl ~= cur_hl then
					if cur_hl ~= 0 then
						u32[r_len], u32[r_len + 1], u32[r_len + 2] = cur_start, col - 1, cur_hl
						r_len = r_len + 3
					end
					cur_hl = cell_hl
					cur_start = col - 1
				end
			end
			if cur_hl ~= 0 then
				u32[r_len], u32[r_len + 1], u32[r_len + 2] = cur_start, last, cur_hl
				r_len = r_len + 3
			end
			ranges[row] = r_len > 0 and ffi.string(u32, r_len * 4) or ""
		end
	end

	commands:set_canvas(id, w, h, transparent, h, runs)
end

--- Creates a reusable drawing context of `width` × `height` cells.
---@param width integer
---@param height integer
---@return markup.canvas.context
function M.context(width, height)
	local ctx = setmetatable({
		width = -1,
		height = -1,
		chars = {},
		widths = {},
		hls = {},
		row_non_unit = {},
		transparent = false,
		-- Rows by run count and ranges; runs flat, in row order.
		_runs = { count = {}, ranges = {}, starts = {}, texts = {}, widths = {}, cells = {} },
		_style_ids = {},
		_scratch = {},
		_u32 = nil,
		_u32_cap = 0,
	}, Context)
	ctx:resize(width, height)
	return ctx
end

return M
