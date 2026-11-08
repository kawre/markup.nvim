--- Small elements built from the primitives.

---@class markup.view.components
local M = {}

local PARTS = { "▏", "▎", "▍", "▌", "▋", "▊", "▉" }

--- The text of a bar, with eighths of a cell of precision.
---@param value number from 0 to 1
---@param width integer
---@return string
function M.bar(value, width)
	local eighths = math.floor(math.max(math.min(value, 1), 0) * width * 8 + 0.5)
	local full = math.floor(eighths / 8)
	return ("█"):rep(full) .. (PARTS[eighths % 8] or "")
end

---@class markup.view.progress
---@field value number|fun(): number from 0 to 1
---@field width integer
---@field style? string color of the bar
---@field track? string background behind it

--- A bar that shows fractions of a cell, so it can move smoothly.
---@param props markup.view.progress
function M.progress(props)
	local m = require("markup")
	local value = props.value

	return m.inline({
		style = props.track,
		width = props.width,
		m.inline(function()
			local current = type(value) == "function" and value() or value
			return M.bar(current, props.width)
		end, props.style),
	})
end

--- Frames of a tail circling the edge of one braille cell, two columns of
--- four dots.
---@param tail integer dots lit at once
---@return string[]
local function snake(tail)
	-- Dot bits by column, then by row.
	local bits = { { 0x01, 0x02, 0x04, 0x40 }, { 0x08, 0x10, 0x20, 0x80 } }
	-- Clockwise from the top left.
	local path = { { 1, 1 }, { 2, 1 }, { 2, 2 }, { 2, 3 }, { 2, 4 }, { 1, 4 }, { 1, 3 }, { 1, 2 } }

	local frames = {}
	for start = 1, #path do
		local cell = 0
		for offset = 0, tail - 1 do
			local dot = path[(start + offset - 1) % #path + 1]
			cell = bit.bor(cell, bits[dot[1]][dot[2]])
		end
		frames[start] = vim.fn.nr2char(0x2800 + cell)
	end
	return frames
end

--- Nerd Font icons from `first` to `last`, codepoints in order.
---@param first integer
---@param last integer
---@return string[]
local function icons(first, last)
	local frames = {}
	for codepoint = first, last do
		frames[#frames + 1] = vim.fn.nr2char(codepoint)
	end
	return frames
end

local function glyphs(...)
	return vim.tbl_map(vim.fn.nr2char, { ... })
end

--- Animated marks for work in progress, each one cell wide. Some spin, others
--- fill, grow, fade or bloom. Needs a Nerd Font.
---@type table<string, { frames: string[], interval: integer }>
M.loaders = {
	-- Braille and blocks.
	dots = { frames = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }, interval = 80 },
	orbit = { frames = { "⣾", "⣽", "⣻", "⢿", "⡿", "⣟", "⣯", "⣷" }, interval = 90 },
	snake = { frames = snake(3), interval = 80 },
	bounce = { frames = { "⠁", "⠂", "⠄", "⡀", "⠄", "⠂" }, interval = 110 },
	pulse = { frames = { "▁", "▂", "▃", "▄", "▅", "▆", "▇", "▆", "▅", "▄", "▃", "▂" }, interval = 80 },
	quadrant = { frames = { "▘", "▝", "▗", "▖" }, interval = 120 },
	flip = { frames = { "▀", "▐", "▄", "▌" }, interval = 120 },
	fill = {
		frames = { "⠀", "⡀", "⡄", "⡆", "⡇", "⣇", "⣧", "⣷", "⣿", "⣷", "⣧", "⣇", "⡇", "⡆", "⡄", "⡀" },
		interval = 70,
	},
	grow = { frames = { "▏", "▎", "▍", "▌", "▋", "▊", "▉", "█", "▉", "▊", "▋", "▌", "▍", "▎" }, interval = 70 },
	shade = { frames = { "░", "▒", "▓", "█", "▓", "▒" }, interval = 120 },

	-- Nerd Font icons.
	-- A dot that grows into a flower and closes again.
	bloom = {
		-- circle_small, circle_medium, circle, flower_outline, flower
		frames = glyphs(0xF09DF, 0xF09DE, 0xF0765, 0xF09F0, 0xF024A, 0xF09F0, 0xF0765, 0xF09DE),
		interval = 120,
	},
	-- A circle filling slice by slice from empty.
	pie = { frames = { vim.fn.nr2char(0xF0766), unpack(icons(0xF0A9E, 0xF0AA5)) }, interval = 100 },
	-- Every phase of the moon, new to new.
	moon = { frames = icons(0xE38D, 0xE3A8), interval = 70 },
	-- The hour hand going round, from twelve.
	clock = {
		frames = { vim.fn.nr2char(0xF144A), unpack(icons(0xF143F, 0xF1449)) },
		interval = 100,
	},
	-- Sand running from the top to the bottom.
	hourglass = { frames = glyphs(0xF251, 0xF252, 0xF253), interval = 300 },
	-- Bars of signal coming in.
	signal = { frames = glyphs(0xF091F, 0xF0922, 0xF0925, 0xF0928), interval = 150 },
	-- A battery charging from empty to full.
	charging = {
		frames = { vim.fn.nr2char(0xF008E), unpack(vim.list_extend(icons(0xF007A, 0xF0082), glyphs(0xF0079))) },
		interval = 100,
	},
}

--- Names of the loaders, in a stable order.
---@return string[]
function M.loader_names()
	local names = vim.tbl_keys(M.loaders)
	table.sort(names)
	return names
end

---@class markup.view.loader
---@field name? string one of `loaders`, a random one by default
---@field style? string
---@field interval? integer ms per frame

local Loader

--- An animated character that runs for as long as it is shown.
---@param props? markup.view.loader
function M.loader(props)
	local m = require("markup")

	Loader = Loader
		or m.component(function(opts)
			local names = M.loader_names()
			local name = opts.name or names[math.random(#names)]
			local loader = M.loaders[name] or error(("unknown loader `%s`"):format(name), 0)

			local frame = m.frames(loader.frames, { interval = opts.interval or loader.interval })
			return m.inline(frame, opts.style)
		end)

	return Loader(props or {})
end

-- The names from before there were loaders that do not spin, kept for the
-- plugins that use them.
M.spinners = M.loaders
M.spinner_names = M.loader_names
M.spinner = M.loader

return M
