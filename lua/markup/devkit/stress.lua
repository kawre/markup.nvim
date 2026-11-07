--- A view that keeps markup busy, with the inspector open beside it: a wave of
--- cells recolored on every frame, meters that keep animating to new values, a
--- long list that churns, panels that open and close, and text that reflows.
---
--- It runs at full throttle: animations move as often as the main loop allows
--- rather than at `Markup.animate.fps`, so frames per second show what the work
--- costs.
---
--- Keys: + / - change the intensity, t toggles the frame cap, <Space> pauses,
--- q closes.

local m = require("markup")
local reactive = require("markup.reactive")

local api = vim.api

local M = {}

local PALETTE = {
	"DiagnosticHint",
	"DiagnosticInfo",
	"Function",
	"DiagnosticOk",
	"String",
	"DiagnosticWarn",
	"Constant",
	"DiagnosticError",
}
local LEVELS = { " ", "▁", "▂", "▃", "▄", "▅", "▆", "▇", "█" }
local WORDS = vim.split(
	"signal effect memo scope layout paint diff patch flex grid block inline cell span wrap clip frame tick ease slide collapse",
	" "
)
local TEXT = ("Markup lays this paragraph out again on every frame, because the box it lives in keeps "
	.. "changing its width. Every line break moves, so the engine has to measure, wrap, paint and diff the whole "
	.. "thing, and Neovim gets a fresh set of lines to write. "):rep(2)

local paused = m.signal(false)
local intensity = m.signal(2)
local capped = m.signal(false)
local fps = 30 ---@type number the rate other views use, restored on close

--- Calls `fn` every `ms` for as long as the calling scope lives, unless paused.
local function every(ms, fn)
	local timer = assert(vim.uv.new_timer())
	timer:start(
		ms,
		ms,
		vim.schedule_wrap(function()
			if not reactive.untrack(paused) then
				fn()
			end
		end)
	)
	reactive.on_cleanup(function()
		if not timer:is_closing() then
			timer:stop()
			timer:close()
		end
	end)
end

local function title(text, note)
	return m.block({
		margin = { 1, 0, 0, 0 },
		m.inline(text, "Title"),
		m.inline(note and ("  " .. note) or "", "Comment"),
	})
end

--- Milliseconds since start, moved forward by the animation clock on every frame.
local function clock()
	local now = m.signal(0)
	Markup.animate.run({
		duration = 1000,
		loop = true,
		update = function()
			if not reactive.untrack(paused) then
				now(vim.uv.hrtime() / 1e6)
			end
		end,
	})
	return now
end

--- Every cell is its own node with its own text and color, all changing on every frame.
local function Wave(now)
	local rows = {}
	for y = 1, 6 do
		local cells = {}
		for x = 1, 64 do
			local function level()
				local t = now() / 400
				local v = math.sin(x / 5 + t) + math.sin((x + y * 3) / 9 - t * 0.7) + math.cos(y / 2 + t * 0.5)
				return (v + 3) / 6
			end
			cells[x] = m.inline({
				function()
					return LEVELS[math.min(math.floor(level() * #LEVELS) + 1, #LEVELS)]
				end,
				style = function()
					return PALETTE[math.min(math.floor(level() * #PALETTE) + 1, #PALETTE)]
				end,
			})
		end
		rows[y] = m.block(cells)
	end
	return rows
end

--- A meter that keeps animating to a new random value on its own timer.
local Meter = m.component(function(props)
	local value = m.animated(math.random(), { duration = 450, easing = "out_cubic" })
	every(300 + (props.index * 37) % 500, function()
		value(math.random())
	end)

	return m.flex({
		gap = 1,
		m.inline(("%02d"):format(props.index), "Comment"),
		m.progress({ value = value, width = 34, style = PALETTE[props.index % #PALETTE + 1] }),
		m.inline(function()
			return ("%3d%%"):format(math.floor(value() * 100))
		end, "Number"),
	})
end)

local function Meters()
	return m.each(function()
		local list = {}
		for i = 1, intensity() * 6 do
			list[i] = i
		end
		return list
	end, function(index)
		return Meter({ index = index })
	end)
end

--- A list that shuffles, inserts and removes rows several times a second.
local function Churn()
	local next_id = 0
	local function item()
		next_id = next_id + 1
		return {
			id = next_id,
			word = WORDS[math.random(#WORDS)],
			size = math.random(4, 24),
			color = PALETTE[math.random(#PALETTE)],
		}
	end

	local items = m.signal({})
	local function fill()
		local list = vim.list_slice(reactive.untrack(items), 1)
		local target = reactive.untrack(intensity) * 40
		while #list < target do
			list[#list + 1] = item()
		end
		while #list > target do
			table.remove(list)
		end
		items(list)
	end
	fill()
	m.effect(function()
		intensity()
		reactive.untrack(fill)
	end)

	every(120, function()
		local list = vim.list_slice(reactive.untrack(items), 1)
		for _ = 1, 4 do
			local i, j = math.random(#list), math.random(#list)
			list[i], list[j] = list[j], list[i]
		end
		table.remove(list, math.random(#list))
		table.insert(list, math.random(#list + 1), item())
		items(list)
	end)

	return m.each(items, function(entry)
		return m.flex({
			gap = 1,
			m.inline(("#%04d"):format(entry.id), "Comment"),
			m.inline(("%-9s"):format(entry.word), entry.color),
			m.inline(("━"):rep(entry.size), entry.color),
		})
	end, {
		key = function(entry)
			return entry.id
		end,
	})
end

--- Panels that open and close in turn.
local function Accordion()
	local open = m.signal(1)
	every(450, function()
		open(reactive.untrack(open) % 5 + 1)
	end)

	local panels = {}
	for i = 1, 5 do
		panels[i] = m.block({
			m.block({
				m.inline(function()
					return open() == i and "▾ " or "▸ "
				end, "Comment"),
				m.inline(("panel %d"):format(i), PALETTE[i]),
			}),
			m.collapse(function()
				return open() == i
			end, function()
				local lines = {}
				for line = 1, 4 do
					lines[line] = m.block({
						padding = { 0, 2 },
						m.inline(("%s %s %s"):format(WORDS[(i * 4 + line) % #WORDS + 1], "·", WORDS[(i + line) % #WORDS + 1]), "Comment"),
					})
				end
				return lines
			end, { duration = 300 }),
		})
	end
	return panels
end

--- A paragraph whose box keeps changing width, so it wraps again on every frame.
local function Reflow()
	local width = m.animated(60, { duration = 1100, easing = "in_out_cubic" })
	local wide = true
	every(1200, function()
		wide = not wide
		width(wide and 60 or 22)
	end)

	return m.block({
		width = function()
			return math.floor(width())
		end,
		padding = { 0, 1 },
		style = "CursorLine",
		TEXT,
	})
end

local function Header(now)
	local started = vim.uv.hrtime() / 1e6
	return m.flex({
		justify = "between",
		padding = { 0, 1 },
		style = "StatusLine",
		m.block({
			m.spinner(),
			m.inline(" markup stress test", "Title"),
			m.inline(function()
				return paused() and "  paused" or ""
			end, "DiagnosticWarn"),
		}),
		m.block({
			m.inline(function()
				return capped() and ("capped at %d fps  "):format(fps) or "full throttle  "
			end, "DiagnosticWarn"),
			m.inline(function()
				return ("intensity %d  "):format(intensity())
			end, "Number"),
			m.inline(function()
				return ("%5.1fs  "):format((now() - started) / 1000)
			end, "Comment"),
			m.inline("+/- intensity  t cap  <Space> pause  q close", "Comment"),
		}),
	})
end

local Stress = m.component(function()
	local now = clock()
	return m.block({
		white_space = "nowrap",
		Header(now),
		m.flex({
			gap = 4,
			padding = { 0, 1 },
			m.block({
				title("Wave", "384 cells, recolored every frame"),
				Wave(now),
				title("Meters", "each animates to a new value on its own timer"),
				Meters(),
				title("Accordion"),
				Accordion(),
				title("Reflow", "wraps again on every frame"),
				m.block({ white_space = "normal", Reflow() }),
			}),
			m.block({
				title("Churn", "shuffles, inserts and removes rows"),
				Churn(),
			}),
		}),
	})
end)

--- Opens the stress test in a new tab, with the inspector beside it.
function M.open()
	vim.cmd.tabnew()
	local win = Markup.window({ position = "current", hijack = true, show = false, minimal = true })
	win.buf = api.nvim_get_current_buf()
	win:show()
	vim.bo[win.buf].buftype = "nofile"
	vim.bo[win.buf].bufhidden = "wipe"

	paused(false)
	capped(false)
	if Markup.animate.fps ~= math.huge then
		fps = Markup.animate.fps
	end
	Markup.animate.set_fps(math.huge)
	local view = Markup.view(win)
	view:render(Stress())

	local tab = api.nvim_get_current_tabpage()
	-- However the tab goes away, other views get their usual rate back.
	api.nvim_create_autocmd("BufWipeout", {
		buffer = win.buf,
		once = true,
		callback = function()
			Markup.animate.set_fps(fps)
		end,
	})

	local function close()
		Markup.animate.set_fps(fps)
		local inspector = Markup.devkit.tree().get(view)
		if inspector then
			inspector:close()
		end
		view:destroy()
		if api.nvim_tabpage_is_valid(tab) and #api.nvim_list_tabpages() > 1 then
			vim.cmd.tabclose(api.nvim_tabpage_get_number(tab))
		end
	end

	win:map("n", "q", close)
	win:map("n", "t", function()
		capped(not capped())
		Markup.animate.set_fps(capped() and fps or math.huge)
	end)
	win:map("n", "<Space>", function()
		paused(not paused())
	end)
	win:map("n", "+", function()
		intensity(math.min(intensity() + 1, 6))
	end)
	win:map("n", "-", function()
		intensity(math.max(intensity() - 1, 1))
	end)

	api.nvim_set_current_win(win.win)
	Markup.devkit.tree().toggle(view)
	api.nvim_set_current_win(win.win)
	return view
end

return M
