--- Lua half of the wire format described in `core/engine/protocol.rs`.
---
--- Commands go into one flat array that is sent once per frame. Appending to a
--- table keeps the hot path inside LuaJIT, and node ids are chosen here so no
--- command needs a reply.

---@class markup.view.protocol
local M = {}

local OP = {
	create = 1,
	create_text = 2,
	set_text = 3,
	set_style = 4,
	insert = 5,
	remove = 6,
	clear = 7,
	resize = 8,
	set_tracks = 9,
	set_cells = 10,
	set_border = 11,
}

M.display = { block = 1, inline = 2, contents = 3, flex = 4, grid = 5 }

M.ROOT = 1

local LENGTH = { auto = -1, fit = -2, full = -3 }

local function length(value)
	return LENGTH[value] or value
end

local function number(value)
	return value
end

local function flag(value)
	return value and 1 or 0
end

--- Stands for "unset", because a flat array cannot hold nil.
local UNSET = -1000000

local function optional(value)
	return value == nil and UNSET or value
end

---@param values table<string, integer>
local function choice(values, name)
	return function(value)
		local encoded = values[value]
		if encoded == nil then
			error(("invalid %s `%s`"):format(name, tostring(value)), 0)
		end
		return encoded
	end
end

local align = choice({ start = 1, ["end"] = 2, center = 3, stretch = 4 }, "align")
local optional_align =
	choice({ start = 1, ["end"] = 2, center = 3, stretch = 4, auto = 0 }, "align")
local distribute = choice(
	{ start = 1, ["end"] = 2, center = 3, between = 4, around = 5, evenly = 6, stretch = 7 },
	"justify"
)
local direction = choice({ row = 0, column = 1 }, "direction")
local position = choice({ static = 0, relative = 1, absolute = 2 }, "position")
local white_space = choice({ normal = 0, nowrap = 1 }, "white_space")

local function optional_white_space(value)
	return value == nil and UNSET or white_space(value)
end

--- Unset inherits, which a flag alone could not say.
local function optional_flag(value)
	if value == nil then
		return UNSET
	end
	return value and 1 or 0
end

--- Style properties by name, with the encoder for each value.
M.style = {
	margin_top = { 1, number },
	margin_right = { 2, number },
	margin_bottom = { 3, number },
	margin_left = { 4, number },
	padding_top = { 5, number },
	padding_right = { 6, number },
	padding_bottom = { 7, number },
	padding_left = { 8, number },
	width = { 9, length },
	height = { 10, length },
	spacing = { 11, number },
	reverse = { 12, flag },
	hl = { 13, number },
	interactive = { 14, flag },
	direction = { 15, direction },
	wrap = { 16, flag },
	justify = { 17, distribute },
	align = { 18, align },
	align_content = { 19, distribute },
	align_self = { 20, optional_align },
	row_gap = { 21, number },
	column_gap = { 22, number },
	grow = { 23, number },
	shrink = { 24, number },
	basis = { 25, length },
	order = { 26, number },
	min_width = { 27, length },
	max_width = { 28, length },
	min_height = { 29, length },
	max_height = { 30, length },
	position = { 31, position },
	top = { 32, optional },
	right = { 33, optional },
	bottom = { 34, optional },
	left = { 35, optional },
	z = { 36, number },
	auto_flow = { 37, direction },
	justify_items = { 38, align },
	justify_self = { 39, optional_align },
	column = { 40, optional },
	row = { 41, optional },
	column_span = { 42, number },
	row_span = { 43, number },
	white_space = { 44, optional_white_space },
	overflow_y = { 45, choice({ visible = 0, hidden = 1, clip = 2 }, "overflow_y") },
	overflow_x = { 46, choice({ visible = 0, hidden = 1, clip = 2 }, "overflow_x") },
	snap = { 47, optional_flag },
	inert = { 48, flag },
}

local TRACK = { auto = 0, cells = 1, fr = 2 }

--- `10`, `"auto"` and `"1fr"` to a kind and a value.
local function track(value)
	if value == "auto" then
		return TRACK.auto, 0
	elseif type(value) == "number" then
		return TRACK.cells, value
	end
	local fraction = type(value) == "string" and tonumber(value:match("^([%d.]+)fr$"))
	if not fraction then
		error(("invalid grid track `%s`"):format(tostring(value)), 0)
	end
	return TRACK.fr, fraction
end

local vim_fn = vim.fn

--- Width of a text, or -1 when the engine can use its byte length. Neovim
--- measures everything else, so `ambiwidth` and `setcellwidths()` are honoured.
local function text_width(text)
	if text:find("[\128-\255]") then
		return vim_fn.strdisplaywidth(text)
	end
	return -1
end

local char_widths = {} ---@type table<string, integer>
local known_cell_widths

--- Forgets measured characters after `setcellwidths()`, which has no event.
function M.check_cell_widths()
	local current = vim.inspect(vim_fn.getcellwidths())
	if current ~= known_cell_widths then
		known_cell_widths = current
		char_widths = {}
	end
end

--- Measured once per character, and only for text that is not ASCII.
local function cell_digits(text)
	local digits, n = {}, 0
	for character in text:gmatch("[\194-\244][\128-\191]*") do
		local width = char_widths[character]
		if not width then
			-- After another character, as text has it: alone, an accent that
			-- joins the character before it would take a cell of its own.
			width = vim_fn.strdisplaywidth("a" .. character) - 1
			char_widths[character] = width
		end
		n = n + 1
		digits[n] = width
	end
	return table.concat(digits)
end

vim.api.nvim_create_autocmd("OptionSet", {
	group = vim.api.nvim_create_augroup("markup.view.widths", { clear = true }),
	pattern = "ambiwidth",
	callback = function()
		char_widths = {}
	end,
})

---@class markup.view.commands
---@field ops any[]
---@field len integer
local Commands = {}
Commands.__index = Commands

---@return markup.view.commands
function M.commands()
	return setmetatable({ ops = {}, len = 0 }, Commands)
end

function Commands:create(id, display)
	local ops, n = self.ops, self.len
	ops[n + 1], ops[n + 2], ops[n + 3] = OP.create, id, display
	self.len = n + 3
end

--- A tab's width depends on where it lands, which only layout knows, so it
--- never reaches the buffer.
local TAB = (" "):rep(4)

local REPLACEMENT = "\u{fffd}"

--- Text with every byte that is not part of a UTF-8 character replaced, as
--- the engine does, so that what Neovim measures is what gets drawn.
local function valid_utf8(text)
	local parts, n, start, at, length = nil, 0, 1, 1, #text
	while at <= length do
		local byte = text:byte(at)
		local size = byte < 0x80 and 1
			or byte >= 0xC2 and byte <= 0xDF and 2
			or byte >= 0xE0 and byte <= 0xEF and 3
			or byte >= 0xF0 and byte <= 0xF4 and 4
			or 0
		local valid = size > 0 and at + size - 1 <= length
		for i = at + 1, at + size - 1 do
			local continuation = text:byte(i)
			valid = valid and continuation >= 0x80 and continuation <= 0xBF
		end
		if valid then
			at = at + size
		else
			parts = parts or {}
			parts[n + 1], parts[n + 2] = text:sub(start, at - 1), REPLACEMENT
			n = n + 2
			at = at + 1
			start = at
		end
	end
	if not parts then
		return text
	end
	parts[n + 1] = text:sub(start)
	return table.concat(parts)
end

--- Text with every byte that is not part of a UTF-8 character replaced, as
--- what is drawn holds it.
M.valid_utf8 = valid_utf8

-- The marker uses the same cell measurements as regular text.
M.style.text_overflow = {
	49,
	function(value)
		if value == nil or value == "clip" then
			return false
		end
		local marker = value == "ellipsis" and "…" or value
		if type(marker) ~= "string" or marker:find("%c") then
			error("text_overflow needs a non-empty, single-line marker", 0)
		end
		marker = valid_utf8(marker)
		local width = vim_fn.strdisplaywidth(marker)
		if width < 1 then
			error("text_overflow needs a non-empty, single-line marker", 0)
		end
		return { marker, width, cell_digits(marker) }
	end,
}

---@param opcode integer
local function write_text(self, opcode, id, text)
	if text:find("\t", 1, true) then
		text = text:gsub("\t", TAB)
	end
	if text:find("[\128-\255]") then
		text = valid_utf8(text)
	end

	if not known_cell_widths then
		M.check_cell_widths()
	end

	local ops, n = self.ops, self.len
	local width = text_width(text)
	ops[n + 1], ops[n + 2], ops[n + 3], ops[n + 4] = opcode, id, text, width
	n = n + 4

	if width >= 0 then
		ops[n + 1], ops[n + 2], ops[n + 3] = OP.set_cells, id, cell_digits(text)
		n = n + 3
	end
	self.len = n
end

function Commands:create_text(id, text)
	write_text(self, OP.create_text, id, text)
end

function Commands:set_text(id, text)
	write_text(self, OP.set_text, id, text)
end

---@param name string
---@param value any
function Commands:set_style(id, name, value)
	local property = M.style[name]
	local ops, n = self.ops, self.len
	ops[n + 1], ops[n + 2], ops[n + 3], ops[n + 4] =
		OP.set_style, id, property[1], property[2](value)
	self.len = n + 4
end

---@param before? integer
function Commands:insert(parent, child, before)
	local ops, n = self.ops, self.len
	ops[n + 1], ops[n + 2], ops[n + 3], ops[n + 4] = OP.insert, parent, child, before or 0
	self.len = n + 4
end

function Commands:remove(id)
	local ops, n = self.ops, self.len
	ops[n + 1], ops[n + 2] = OP.remove, id
	self.len = n + 2
end

function Commands:clear(id)
	local ops, n = self.ops, self.len
	ops[n + 1], ops[n + 2] = OP.clear, id
	self.len = n + 2
end

--- A number makes that many equal tracks.
---@param axis "columns"|"rows"
---@param tracks integer|(integer|string)[]
function Commands:set_tracks(id, axis, tracks)
	if type(tracks) == "number" then
		local count = tracks
		tracks = {}
		for i = 1, count do
			tracks[i] = "1fr"
		end
	end

	local ops, n = self.ops, self.len
	ops[n + 1], ops[n + 2], ops[n + 3], ops[n + 4] =
		OP.set_tracks, id, axis == "rows" and 0 or 1, #tracks
	n = n + 4
	for _, value in ipairs(tracks) do
		ops[n + 1], ops[n + 2] = track(value)
		n = n + 2
	end
	self.len = n
end

local SIDES = { top = 1, right = 2, bottom = 4, left = 8 }

--- Top left, top, top right, right, bottom right, bottom, bottom left, left.
M.borders = {
	single = { chars = "┌─┐│┘─└│" },
	rounded = { chars = "╭─╮│╯─╰│" },
	double = { chars = "╔═╗║╝═╚║" },
	heavy = { chars = "┏━┓┃┛━┗┃" },
	-- Cells are twice as tall as wide, so a half cell edge matches one column.
	half = {
		chars = "▄▄▄ ▀▀▀ ",
		sides = { "top", "bottom" },
		outside_background = true,
	},
}

---@param preset string|{ chars: string }
---@param sides? string[]
---@param hl_id integer
function Commands:set_border(id, preset, sides, hl_id)
	local border = type(preset) == "table" and preset or M.borders[preset]
	if not border then
		error(("invalid border `%s`"):format(tostring(preset)), 0)
	end

	local mask = 0
	for _, side in ipairs(sides or border.sides or { "top", "right", "bottom", "left" }) do
		mask = mask + (SIDES[side] or error(("invalid border side `%s`"):format(tostring(side)), 0))
	end

	local ops, n = self.ops, self.len
	ops[n + 1], ops[n + 2], ops[n + 3], ops[n + 4] = OP.set_border, id, border.chars, mask
	ops[n + 5], ops[n + 6] = hl_id, flag(border.outside_background)
	self.len = n + 6
end

function Commands:resize(width)
	local ops, n = self.ops, self.len
	ops[n + 1], ops[n + 2] = OP.resize, width
	self.len = n + 2
end

return M
