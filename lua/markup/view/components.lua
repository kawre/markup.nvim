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

---@class markup.view.loader_def
---@field frames string[]
---@field interval integer ms per frame
---@field nerd_font? true needs a Nerd Font to show

--- Animated marks for work in progress, each one cell wide. Some spin, others
--- fill, grow, fade or bloom. Those marked `nerd_font` need a Nerd Font;
--- `pick` draws from some of them.
---@type table<string, markup.view.loader_def>
M.loaders = {
	-- Braille and blocks.
	dots = {
		frames = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" },
		interval = 80,
	},
	orbit = { frames = { "⣾", "⣽", "⣻", "⢿", "⡿", "⣟", "⣯", "⣷" }, interval = 90 },
	snake = { frames = snake(3), interval = 80 },
	bounce = { frames = { "⠁", "⠂", "⠄", "⡀", "⠄", "⠂" }, interval = 110 },
	pulse = {
		frames = {
			"▁",
			"▂",
			"▃",
			"▄",
			"▅",
			"▆",
			"▇",
			"▆",
			"▅",
			"▄",
			"▃",
			"▂",
		},
		interval = 80,
	},
	quadrant = { frames = { "▘", "▝", "▗", "▖" }, interval = 120 },
	flip = { frames = { "▀", "▐", "▄", "▌" }, interval = 120 },
	fill = {
		frames = {
			"⠀",
			"⡀",
			"⡄",
			"⡆",
			"⡇",
			"⣇",
			"⣧",
			"⣷",
			"⣿",
			"⣷",
			"⣧",
			"⣇",
			"⡇",
			"⡆",
			"⡄",
			"⡀",
		},
		interval = 70,
	},
	grow = {
		frames = {
			"▏",
			"▎",
			"▍",
			"▌",
			"▋",
			"▊",
			"▉",
			"█",
			"▉",
			"▊",
			"▋",
			"▌",
			"▍",
			"▎",
		},
		interval = 70,
	},
	shade = { frames = { "░", "▒", "▓", "█", "▓", "▒" }, interval = 120 },

	-- Nerd Font icons: things that grow, open, turn or run out.
	-- A dot that grows into a flower and closes again.
	bloom = {
		-- circle_small, circle_medium, circle, flower_outline, flower
		frames = glyphs(0xF09DF, 0xF09DE, 0xF0765, 0xF09F0, 0xF024A, 0xF09F0, 0xF0765, 0xF09DE),
		interval = 120,
		nerd_font = true,
	},
	-- A seed that sprouts into a tulip and goes back to seed.
	sprout = {
		-- circle_small, seed_outline, seed, sprout_outline, sprout,
		-- flower_tulip_outline, flower_tulip
		frames = glyphs(
			0xF09DF,
			0xF0E63,
			0xF0E62,
			0xF0E67,
			0xF0E66,
			0xF09F2,
			0xF09F1,
			0xF09F2,
			0xF0E66,
			0xF0E67,
			0xF0E62,
			0xF0E63
		),
		interval = 130,
		nerd_font = true,
	},
	-- A dot that opens into a poppy full of pollen.
	poppy = {
		-- circle_small, circle_medium, circle, flower_pollen_outline,
		-- flower_pollen, flower_poppy
		frames = glyphs(
			0xF09DF,
			0xF09DE,
			0xF0765,
			0xF1886,
			0xF1885,
			0xF0D08,
			0xF1885,
			0xF1886,
			0xF0765,
			0xF09DE
		),
		interval = 120,
		nerd_font = true,
	},
	-- A dot that lights into a star and sparkles.
	twinkle = {
		-- circle_small, star_four_points_outline, star_four_points, creation, shimmer
		frames = glyphs(0xF09DF, 0xF0AE3, 0xF0AE2, 0xF0674, 0xF1545, 0xF0674, 0xF0AE2, 0xF0AE3),
		interval = 120,
		nerd_font = true,
	},
	-- A dot spreading in rings, as on water.
	ripple = {
		-- circle_small, circle_medium, circle, record_circle_outline,
		-- circle_double, circle_outline
		frames = glyphs(0xF09DF, 0xF09DE, 0xF0765, 0xF0EC3, 0xF0E95, 0xF0766, 0xF0E95, 0xF0EC3),
		interval = 110,
		nerd_font = true,
	},
	-- Every phase of the moon, new to new.
	moon = { frames = icons(0xE38D, 0xE3A8), interval = 70, nerd_font = true },
	-- The same phases, drawn in outline.
	moon_alt = {
		frames = vim.list_extend(icons(0xE3C8, 0xE3E2), glyphs(0xE3E3)),
		interval = 70,
		nerd_font = true,
	},
	-- Sand running from the top to the bottom.
	hourglass = { frames = glyphs(0xF251, 0xF252, 0xF253), interval = 300, nerd_font = true },
	-- The same, in four steps: full, running, run out and empty.
	-- timer_sand_full, timer_sand, timer_sand_complete, timer_sand_empty
	sand = { frames = glyphs(0xF078C, 0xF051F, 0xF199F, 0xF06AD), interval = 300, nerd_font = true },
}

--- How many cells the widest frame of a loader takes.
---@param loader markup.view.loader_def
---@return integer
function M.loader_width(loader)
	local width = 0
	for _, frame in ipairs(loader.frames) do
		width = math.max(width, vim.api.nvim_strwidth(frame))
	end
	return width
end

---@class markup.view.loader_pick
---@field nerd_font? boolean true for only the loaders that need a Nerd Font, false for only those that do not
---@field width? integer only the loaders this many cells wide
---@field names? string[] only these loaders

--- Names of the loaders, in a stable order: all of them, or those `pick`
--- allows.
---@param pick? markup.view.loader_pick
---@return string[]
function M.loader_names(pick)
	pick = pick or {}
	local allowed = pick.names and {}
	for _, name in ipairs(pick.names or {}) do
		allowed[name] = true
	end
	local names = {}
	for name, loader in pairs(M.loaders) do
		if
			(not allowed or allowed[name])
			and (pick.nerd_font == nil or pick.nerd_font == (loader.nerd_font == true))
			and (pick.width == nil or pick.width == M.loader_width(loader))
		then
			names[#names + 1] = name
		end
	end
	table.sort(names)
	return names
end

---@class markup.view.loader
---@field name? string one of `loaders`, a random one by default
---@field pick? markup.view.loader_pick which loaders the random one is drawn from
---@field style? string
---@field interval? integer ms per frame

local Loader

--- An animated character that runs for as long as it is shown.
---@param props? markup.view.loader
function M.loader(props)
	local m = require("markup")

	Loader = Loader
		or m.component(function(opts)
			local name = opts.name
			if not name then
				local names = M.loader_names(opts.pick)
				name = names[math.random(#names)]
					or error(("no loader matches %s"):format(vim.inspect(opts.pick)), 0)
			end
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
