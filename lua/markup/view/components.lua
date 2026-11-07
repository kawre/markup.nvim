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

--- Frames of each spinner, every one a single cell wide. Only characters that
--- common coding fonts have, such as JetBrains Mono, Cascadia and Noto Sans Mono,
--- so that none shows as a box or leans on a fallback font.
---@type table<string, { frames: string[], interval: integer }>
M.spinners = {
	dots = { frames = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }, interval = 80 },
	braille = { frames = { "⣾", "⣽", "⣻", "⢿", "⡿", "⣟", "⣯", "⣷" }, interval = 80 },
	bounce = { frames = { "⠁", "⠂", "⠄", "⡀", "⢀", "⠠", "⠐", "⠈" }, interval = 90 },
	quarters = { frames = { "▖", "▘", "▝", "▗" }, interval = 110 },
	grow = { frames = { "▁", "▂", "▃", "▄", "▅", "▆", "▇", "█", "▇", "▆", "▅", "▄", "▃", "▂" }, interval = 70 },
	blocks = { frames = { "▏", "▎", "▍", "▌", "▋", "▊", "▉", "█", "▉", "▊", "▋", "▌", "▍", "▎" }, interval = 70 },
	box = { frames = { "┤", "┘", "┴", "└", "├", "┌", "┬", "┐" }, interval = 100 },
	corners = { frames = { "╭", "╮", "╯", "╰" }, interval = 120 },
	squish = { frames = { "▌", "▀", "▐", "▄" }, interval = 120 },
	shade = { frames = { "░", "▒", "▓", "█", "▓", "▒" }, interval = 100 },
	line = { frames = { "-", "\\", "|", "/" }, interval = 110 },
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
