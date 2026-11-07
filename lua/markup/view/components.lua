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

--- Frames of a tail circling the edge of two braille cells, which have four
--- columns of four dots between them.
---@param tail integer dots lit at once
---@return string[]
local function snake(tail)
	-- Dot bits by column within a cell, then by row.
	local bits = { { 0x01, 0x02, 0x04, 0x40 }, { 0x08, 0x10, 0x20, 0x80 } }

	local path = {}
	for col = 0, 3 do
		path[#path + 1] = { col, 0 }
	end
	for row = 1, 3 do
		path[#path + 1] = { 3, row }
	end
	for col = 2, 0, -1 do
		path[#path + 1] = { col, 3 }
	end
	for row = 2, 1, -1 do
		path[#path + 1] = { 0, row }
	end

	local frames = {}
	for start = 1, #path do
		local cells = { 0, 0 }
		for offset = 0, tail - 1 do
			local dot = path[(start + offset - 1) % #path + 1]
			local cell = math.floor(dot[1] / 2) + 1
			cells[cell] = bit.bor(cells[cell], bits[dot[1] % 2 + 1][dot[2] + 1])
		end
		frames[start] = vim.fn.nr2char(0x2800 + cells[1]) .. vim.fn.nr2char(0x2800 + cells[2])
	end
	return frames
end

--- A few spinners that read clearly as motion. Only braille and block
--- characters, which coding fonts such as JetBrains Mono and Cascadia have in
--- full. All frames of a spinner share their width.
---@type table<string, { frames: string[], interval: integer }>
M.spinners = {
	dots = { frames = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }, interval = 80 },
	orbit = { frames = { "⣾", "⣽", "⣻", "⢿", "⡿", "⣟", "⣯", "⣷" }, interval = 90 },
	snake = { frames = snake(4), interval = 70 },
	pulse = { frames = { "▁", "▂", "▃", "▄", "▅", "▆", "▇", "▆", "▅", "▄", "▃", "▂" }, interval = 80 },
}

--- Names of the spinners, in a stable order.
---@return string[]
function M.spinner_names()
	local names = vim.tbl_keys(M.spinners)
	table.sort(names)
	return names
end

---@class markup.view.spinner
---@field name? string one of `spinners`, a random one by default
---@field style? string
---@field interval? integer ms per frame

local Spinner

--- An animated character that runs for as long as it is shown.
---@param props? markup.view.spinner
function M.spinner(props)
	local m = require("markup")

	Spinner = Spinner
		or m.component(function(opts)
			local names = M.spinner_names()
			local name = opts.name or names[math.random(#names)]
			local spinner = M.spinners[name] or error(("unknown spinner `%s`"):format(name), 0)

			local frame = m.frames(spinner.frames, { interval = opts.interval or spinner.interval })
			return m.inline(frame, opts.style)
		end)

	return Spinner(props or {})
end

return M
