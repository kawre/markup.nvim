--- A view that keeps markup busy, with the inspector open beside it. Each
--- workload has its own amount, set from a popup (`s`), from nothing to far more
--- than a real UI would ever ask for:
---
--- - wave: cells recolored on every frame
--- - meters: progress bars animating to new values on their own timers
--- - churn: a long list that shuffles, inserts and removes rows
--- - accordion: panels that open and close in turn
--- - reflow: paragraphs whose box keeps changing width
--- - cards: a grid of bordered cards, each with a tint, spinner and meter
--- - carousel: pages that slide in turn
--- - tree: recursive components, deep, whose branches open and close
--- - rich text: paragraphs of many styled spans whose styles keep moving
--- - highlights: animated highlight groups, set on every frame
--- - spinners: many spinners at once
---
--- It runs at full throttle: animations move as often as the main loop allows
--- rather than at `Markup.animate.fps`, so frames per second show what the work
--- costs.
---
--- Keys: s settings, + / - next or previous preset, t toggles the frame cap,
--- <Space> pauses, q closes.

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

--- Every amount the popup can set, in the order it lists them. `values` are
--- the steps of its slider, and 0 turns the workload off.
---@type { key: string, label: string, unit: string, values: number[], presets: integer[] }[]
M.settings = {
	{ key = "wave", label = "Wave", unit = "rows", values = { 0, 2, 4, 6, 12, 18, 24 } },
	{ key = "meters", label = "Meters", unit = "bars", values = { 0, 6, 12, 24, 48, 96, 160 } },
	{ key = "churn", label = "Churn", unit = "rows", values = { 0, 20, 40, 80, 160, 320, 640, 1280, 2560 } },
	{ key = "churn_rate", label = "Churn rate", unit = "ms", values = { 1000, 500, 250, 120, 60, 30, 15 } },
	{ key = "accordion", label = "Accordion", unit = "panels", values = { 0, 3, 5, 10, 20, 40 } },
	{ key = "reflow", label = "Reflow", unit = "texts", values = { 0, 1, 2, 4, 8, 16 } },
	{ key = "cards", label = "Cards", unit = "cards", values = { 0, 4, 8, 16, 32, 64, 128 } },
	{ key = "carousel", label = "Carousel", unit = "rows", values = { 0, 1, 2, 4, 8 } },
	{ key = "tree", label = "Tree", unit = "levels", values = { 0, 3, 4, 5, 6, 7, 8 } },
	{ key = "text", label = "Rich text", unit = "texts", values = { 0, 1, 2, 4, 8, 16 } },
	{ key = "highlights", label = "Highlights", unit = "groups", values = { 0, 10, 25, 50, 100, 200, 400 } },
	{ key = "spinners", label = "Spinners", unit = "", values = { 0, 1, 5, 10, 25, 50, 100 } },
}

--- Presets pick a step of every slider, in the order of `M.settings`.
M.presets = {
	{ name = "idle", steps = { 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1 } },
	{ name = "light", steps = { 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2 } },
	{ name = "medium", steps = { 4, 3, 4, 4, 3, 2, 3, 2, 3, 3, 3, 3 } },
	{ name = "heavy", steps = { 5, 5, 6, 5, 4, 4, 5, 3, 5, 4, 5, 5 } },
	{ name = "insane", steps = { 7, 7, 9, 7, 6, 6, 7, 5, 7, 6, 7, 7 } },
}

local paused = m.signal(false)
local capped = m.signal(false)
local fps = 60 ---@type number the rate other views use, restored on close

---@type table<string, markup.reactive.signal> the step each slider is at
local steps = {}
for _, setting in ipairs(M.settings) do
	steps[setting.key] = m.signal(1)
end

--- The amount a setting is at.
---@param key string
local function amount(key)
	for _, setting in ipairs(M.settings) do
		if setting.key == key then
			return setting.values[steps[key]()]
		end
	end
end
M.amount = amount

---@param name string
function M.apply_preset(name)
	for _, preset in ipairs(M.presets) do
		if preset.name == name then
			for i, setting in ipairs(M.settings) do
				steps[setting.key](preset.steps[i])
			end
		end
	end
end

--- The preset everything is set to, or nil when it has been changed by hand.
function M.preset()
	for _, preset in ipairs(M.presets) do
		local same = true
		for i, setting in ipairs(M.settings) do
			if steps[setting.key]() ~= preset.steps[i] then
				same = false
				break
			end
		end
		if same then
			return preset.name
		end
	end
end

---@param key string
---@param by integer
function M.step(key, by)
	for _, setting in ipairs(M.settings) do
		if setting.key == key then
			local index = reactive.untrack(steps[key]) + by
			steps[key](math.max(math.min(index, #setting.values), 1))
		end
	end
end

--- Calls `fn` every `ms` for as long as the calling scope lives, unless paused.
--- `ms` may be a function, read on every turn, to follow a setting.
local function every(ms, fn)
	local timer = assert(vim.uv.new_timer())
	local waited = 0
	local tick = 15
	local fixed = type(ms) == "number" and ms
	timer:start(
		fixed or tick,
		fixed or tick,
		vim.schedule_wrap(function()
			if reactive.untrack(paused) then
				return
			end
			if fixed then
				fn()
				return
			end
			waited = waited + tick
			if waited >= reactive.untrack(ms) then
				waited = 0
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

--- 1..n as a list, for `m.each`.
local function range(n)
	local list = {}
	for i = 1, n do
		list[i] = i
	end
	return list
end

--- Shows `render(amount)` while the setting is on.
local function section(key, title, note, render)
	return m.show(function()
		return amount(key) > 0
	end, function()
		return m.block({
			m.block({
				margin = { 1, 0, 0, 0 },
				m.inline(title, "Title"),
				m.inline("  " .. note, "Comment"),
			}),
			render(function()
				return amount(key)
			end),
		})
	end)
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

local function color(group)
	return Markup.animate.color(group, "fg") or 0x89b4fa
end

local function background()
	return Markup.animate.color("Normal", "bg") or 0x1e1e2e
end

--- Every cell is its own node with its own text and color, all changing on every frame.
local function Wave(now, rows)
	return m.each(function()
		return range(rows())
	end, function(y)
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
		return m.block(cells)
	end)
end

--- A meter that keeps animating to a new random value on its own timer.
local Meter = m.component(function(props)
	local value = m.animated(math.random(), { duration = 450, easing = "out_cubic" })
	every(300 + (props.index * 37) % 500, function()
		value(math.random())
	end)

	return m.flex({
		gap = 1,
		m.inline(("%03d"):format(props.index), "Comment"),
		m.progress({ value = value, width = props.width or 34, style = PALETTE[props.index % #PALETTE + 1] }),
		m.inline(function()
			return ("%3d%%"):format(math.floor(value() * 100))
		end, "Number"),
	})
end)

local function Meters(count)
	return m.each(function()
		return range(count())
	end, function(index)
		return Meter({ index = index })
	end)
end

--- A list that shuffles, inserts and removes rows, as often as its rate says.
local Churn = m.component(function(props)
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
	m.effect(function()
		local target = props.size()
		local list = vim.list_slice(reactive.untrack(items), 1)
		while #list < target do
			list[#list + 1] = item()
		end
		while #list > target do
			table.remove(list)
		end
		items(list)
	end)

	every(function()
		return amount("churn_rate")
	end, function()
		local list = vim.list_slice(reactive.untrack(items), 1)
		if #list == 0 then
			return
		end
		for _ = 1, math.max(4, math.floor(#list / 40)) do
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
			m.inline(("#%05d"):format(entry.id), "Comment"),
			m.inline(("%-9s"):format(entry.word), entry.color),
			m.inline(("━"):rep(entry.size), entry.color),
		})
	end, {
		key = function(entry)
			return entry.id
		end,
	})
end)

--- Panels that open and close in turn.
local Accordion = m.component(function(props)
	local open = m.signal(1)
	every(450, function()
		open(reactive.untrack(open) % math.max(reactive.untrack(props.count), 1) + 1)
	end)

	return m.each(function()
		return range(props.count())
	end, function(i)
		return m.block({
			m.block({
				m.inline(function()
					return open() == i and "▾ " or "▸ "
				end, "Comment"),
				m.inline(("panel %d"):format(i), PALETTE[i % #PALETTE + 1]),
			}),
			m.collapse(function()
				return open() == i
			end, function()
				local lines = {}
				for line = 1, 4 do
					lines[line] = m.block({
						padding = { 0, 2 },
						m.inline(
							("%s · %s"):format(WORDS[(i * 4 + line) % #WORDS + 1], WORDS[(i + line) % #WORDS + 1]),
							"Comment"
						),
					})
				end
				return lines
			end, { duration = 300 }),
		})
	end)
end)

--- A paragraph whose box keeps changing width, so it wraps again on every frame.
local Reflow = m.component(function(props)
	local width = m.animated(60, { duration = 1100, easing = "in_out_cubic" })
	local wide = props.index % 2 == 0
	every(1200 + props.index * 70, function()
		wide = not wide
		width(wide and 60 or 22)
	end)

	return m.block({
		white_space = "normal",
		margin = { 0, 0, 1, 0 },
		m.block({
			width = function()
				return math.floor(width())
			end,
			padding = { 0, 1 },
			style = "CursorLine",
			TEXT,
		}),
	})
end)

local function Reflows(count)
	return m.each(function()
		return range(count())
	end, function(index)
		return Reflow({ index = index })
	end)
end

--- A bordered card: a tinted background, a spinner, a meter and nested flex rows.
local Card = m.component(function(props)
	local accent = PALETTE[props.index % #PALETTE + 1]
	local light = m.animated(0, { duration = 600, easing = "in_out_cubic" })
	local value = m.animated(math.random(), { duration = 500 })
	every(700 + (props.index * 53) % 600, function()
		light(reactive.untrack(light) > 0.5 and 0 or 1)
		value(math.random())
	end)
	local tint = Markup.animate.tint(
		{ bg = background() },
		{ bg = Markup.animate.mix(background(), color(accent), 0.25) },
		light
	)

	return m.block({
		border = "rounded",
		border_style = accent,
		style = tint,
		padding = { 0, 1 },
		m.flex({
			justify = "between",
			m.block({ m.loader(), m.inline((" card %d"):format(props.index), accent) }),
			m.inline(function()
				return ("%3d%%"):format(math.floor(value() * 100))
			end, "Number"),
		}),
		m.flex({
			gap = 1,
			m.inline(WORDS[props.index % #WORDS + 1], "Comment"),
			m.inline(WORDS[(props.index * 7) % #WORDS + 1], "Comment"),
		}),
		m.progress({ value = value, width = 18, style = accent }),
	})
end)

local function Cards(count)
	return m.grid({
		columns = 3,
		gap = { 0, 1 },
		m.each(function()
			return range(count())
		end, function(index)
			return Card({ index = index })
		end),
	})
end

--- Pages sliding in turn.
local Carousel = m.component(function(props)
	local page = m.signal(1)
	every(900 + props.index * 110, function()
		page(reactive.untrack(page) % 4 + 1)
	end)

	return m.block({
		margin = { 0, 0, 1, 0 },
		m.slide(page, function(key)
			local accent = PALETTE[(key + props.index) % #PALETTE + 1]
			return m.block({
				border = "rounded",
				border_style = accent,
				padding = { 0, 2 },
				m.inline(("carousel %d · page %d"):format(props.index, key), accent),
				m.block({ m.inline(("%s %s %s"):format(WORDS[key], WORDS[key + 4], WORDS[key + 8]), "Comment") }),
			})
		end),
	})
end)

local function Carousels(count)
	return m.each(function()
		return range(count())
	end, function(index)
		return Carousel({ index = index })
	end)
end

--- Recursive components, a branch per level, whose branches open and close.
local Branch
Branch = m.component(function(props)
	local open = m.signal(props.level < 3)
	props.branches[#props.branches + 1] = open
	m.on_cleanup(function()
		for i, branch in ipairs(props.branches) do
			if branch == open then
				table.remove(props.branches, i)
				break
			end
		end
	end)

	local function children()
		if props.level >= props.depth then
			return m.block({ padding = { 0, 2 }, m.inline(("leaf %s"):format(props.path), "String") })
		end
		local kids = {}
		for i = 1, 2 do
			kids[i] = Branch({
				level = props.level + 1,
				depth = props.depth,
				path = props.path .. "." .. i,
				branches = props.branches,
			})
		end
		return m.block({ padding = { 0, 0, 0, 2 }, kids })
	end

	return m.block({
		m.block({
			m.inline(function()
				return open() and "▾ " or "▸ "
			end, "Comment"),
			m.inline(("node %s"):format(props.path), PALETTE[props.level % #PALETTE + 1]),
		}),
		m.collapse(open, children, { duration = 150 }),
	})
end)

local Tree = m.component(function(props)
	local branches = {}
	every(120, function()
		if #branches > 0 then
			local branch = branches[math.random(#branches)]
			branch(not reactive.untrack(branch))
		end
	end)
	return function()
		return Branch({ level = 1, depth = props.depth(), path = "1", branches = branches })
	end
end)

--- Paragraphs of styled spans whose styles keep moving along the words.
local RichText = m.component(function(props)
	local phase = m.signal(0)
	every(140, function()
		phase(reactive.untrack(phase) + 1)
	end)

	local spans = {}
	for i = 1, 60 do
		local word = WORDS[(i * 7 + props.index) % #WORDS + 1]
		spans[#spans + 1] = m.inline({
			word .. " ",
			style = function()
				local p = (i + phase()) % 12
				if p == 0 then
					return "Title"
				elseif p < 4 then
					return PALETTE[(i + phase()) % #PALETTE + 1]
				end
				return nil
			end,
		})
	end
	return m.block({ white_space = "normal", margin = { 0, 0, 1, 0 }, spans })
end)

local function Texts(count)
	return m.each(function()
		return range(count())
	end, function(index)
		return RichText({ index = index })
	end)
end

--- A chip whose own highlight group is set again on every frame it moves.
local Chip = m.component(function(props)
	local accent = color(PALETTE[props.index % #PALETTE + 1])
	local glow = m.animated(0, { duration = 400 + props.index % 7 * 60 })
	every(450 + props.index % 9 * 50, function()
		glow(reactive.untrack(glow) > 0.5 and 0 or 1)
	end)
	local group = Markup.animate.tint({ fg = background(), bg = background() }, { fg = background(), bg = accent }, glow)
	return m.inline((" %03d "):format(props.index), group)
end)

local function Highlights(count)
	return m.block({
		white_space = "normal",
		m.each(function()
			return range(count())
		end, function(index)
			return Chip({ index = index })
		end),
	})
end

local function Spinners(count)
	return m.block({
		white_space = "normal",
		m.each(function()
			return range(count())
		end, function(index)
			return m.inline({ m.loader({ style = PALETTE[index % #PALETTE + 1] }), " " })
		end),
	})
end

local function Header(now)
	local started = vim.uv.hrtime() / 1e6
	return m.flex({
		justify = "between",
		padding = { 0, 1 },
		style = "StatusLine",
		m.block({
			m.loader(),
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
				return (M.preset() or "custom") .. "  "
			end, "Number"),
			m.inline(function()
				return ("%5.1fs  "):format((now() - started) / 1000)
			end, "Comment"),
			m.inline("s settings  +/- preset  t cap  <Space> pause  q close", "Comment"),
		}),
	})
end

local Stress = m.component(function()
	local now = clock()
	return m.block({
		white_space = "nowrap",
		Header(now),
		m.block({
			padding = { 0, 1 },
			section("carousel", "Carousel", "pages slide in turn", Carousels),
		}),
		m.flex({
			gap = 4,
			padding = { 0, 1 },
			-- As wide as a row of the wave, so neither column squeezes the other.
			m.block({
				width = 66,
				shrink = 0,
				section("wave", "Wave", "64 cells a row, recolored every frame", function(rows)
					return Wave(now, rows)
				end),
				section("meters", "Meters", "each animates on its own timer", Meters),
				section("cards", "Cards", "borders, tints, spinners and meters", Cards),
				section("accordion", "Accordion", "panels open and close", function(count)
					return Accordion({ count = count })
				end),
				section("reflow", "Reflow", "wraps again on every frame", Reflows),
				section("text", "Rich text", "styles move along the words", Texts),
			}),
			m.block({
				grow = 1,
				section("tree", "Tree", "branches open and close, two per level", function(depth)
					return Tree({ depth = depth })
				end),
				section("highlights", "Highlights", "a group each, set on every frame", Highlights),
				section("spinners", "Spinners", "", Spinners),
				section("churn", "Churn", "shuffles, inserts and removes rows", function(size)
					return Churn({ size = size })
				end),
			}),
		}),
	})
end)

--- The popup that sets every workload.
---@param view markup.view the stress test
local function open_settings(view)
	if M.settings_win and M.settings_win:win_valid() then
		M.settings_win:focus()
		return
	end

	local rows = #M.settings + 7
	local width = 60
	local target = view.win.win
	local win = Markup.window({
		position = "float",
		relative = "win",
		win = target,
		width = width,
		height = rows,
		row = 2,
		col = math.max(math.floor((api.nvim_win_get_width(target) - width) / 2), 0),
		border = "rounded",
		title = " Stress test ",
		title_pos = "center",
		footer = " h/l change  <CR> press  q close ",
		footer_pos = "center",
		enter = true,
		focusable = true,
		minimal = true,
		backdrop = false,
	})
	M.settings_win = win
	local popup = Markup.view(win, { snap = true, hide_cursor = true })
	popup.devtool = true
	M.settings_view = popup

	local hovered = m.signal(nil) ---@type string?
	local function hover(key)
		return function(on)
			if on then
				hovered(key)
			elseif reactive.untrack(hovered) == key then
				hovered(nil)
			end
		end
	end
	local function row_style(key)
		return function()
			return hovered() == key and "MarkupInspectorSelected" or nil
		end
	end

	local presets = { m.inline("Preset   ", "MarkupInspectorStrong") }
	for _, preset in ipairs(M.presets) do
		local key = "preset:" .. preset.name
		presets[#presets + 1] = m.inline({
			(" %s "):format(preset.name),
			on_press = function()
				M.apply_preset(preset.name)
			end,
			on_hover = hover(key),
			style = function()
				if hovered() == key then
					return "MarkupInspectorSelected"
				end
				return M.preset() == preset.name and "MarkupInspectorGood" or "MarkupInspectorLabel"
			end,
		})
		presets[#presets + 1] = m.inline(" ")
	end

	local SLIDER = 16
	local lines = { m.block({ padding = { 0, 1 }, presets }), m.block("") }
	for _, setting in ipairs(M.settings) do
		local step = steps[setting.key]
		local function filled()
			return math.floor((step() - 1) / (#setting.values - 1) * (SLIDER - 1))
		end
		lines[#lines + 1] = m.block({
			padding = { 0, 1 },
			style = row_style(setting.key),
			on_hover = hover(setting.key),
			on_press = function()
				local at = reactive.untrack(step)
				step(at == #setting.values and 1 or at + 1)
			end,
			m.flex({
				justify = "between",
				m.block({
					m.inline(("%-12s"):format(setting.label), function()
						return setting.values[step()] == 0 and "MarkupInspectorLabel" or "MarkupInspectorStrong"
					end),
					m.inline(function()
						return ("━"):rep(filled())
					end, "MarkupInspectorGood"),
					m.inline("●", "MarkupInspectorStrong"),
					m.inline(function()
						return ("─"):rep(SLIDER - 1 - filled())
					end, "MarkupInspectorGuide"),
				}),
				m.inline(function()
					local value = setting.values[step()]
					if value == 0 then
						return "off"
					end
					return ("%d %s"):format(value, setting.unit)
				end, "MarkupInspectorValue"),
			}),
		})
	end

	local function toggle(key, label, signal, apply)
		return m.block({
			padding = { 0, 1 },
			style = row_style(key),
			on_hover = hover(key),
			on_press = function()
				signal(not reactive.untrack(signal))
				if apply then
					apply()
				end
			end,
			m.inline(function()
				return signal() and "\u{f0132} " or "\u{f0131} "
			end, function()
				return signal() and "MarkupInspectorGood" or "MarkupInspectorLabel"
			end),
			m.inline(label, "MarkupInspectorValue"),
		})
	end
	lines[#lines + 1] = m.block("")
	lines[#lines + 1] = toggle("paused", "Paused", paused)
	lines[#lines + 1] = toggle("capped", "Cap the frame rate", capped, function()
		Markup.animate.set_fps(reactive.untrack(capped) and fps or math.huge)
	end)

	popup:render(m.block({ white_space = "nowrap", lines }))

	local function change(by)
		local key = reactive.untrack(hovered)
		if key and steps[key] then
			M.step(key, by)
		end
	end
	for _, lhs in ipairs({ "h", "<Left>" }) do
		win:map("n", lhs, function()
			change(-1)
		end)
	end
	for _, lhs in ipairs({ "l", "<Right>" }) do
		win:map("n", lhs, function()
			change(1)
		end)
	end
	for _, lhs in ipairs({ "<CR>", "<Space>" }) do
		win:map("n", lhs, function()
			popup:press()
		end)
	end
	local function close()
		M.close_settings()
		if api.nvim_win_is_valid(target) then
			api.nvim_set_current_win(target)
		end
	end
	for _, lhs in ipairs({ "q", "<Esc>", "s" }) do
		win:map("n", lhs, close)
	end
	api.nvim_create_autocmd("WinLeave", {
		buffer = win.buf,
		once = true,
		callback = function()
			vim.schedule(M.close_settings)
		end,
	})
end

function M.close_settings()
	if M.settings_view then
		M.settings_view:destroy()
		M.settings_view = nil
	end
	if M.settings_win and M.settings_win:win_valid() then
		M.settings_win:close()
	end
	M.settings_win = nil
end

--- Opens the stress test in a new tab, with the inspector beside it.
---@param opts? { preset?: string, settings?: boolean } `settings` opens the popup
function M.open(opts)
	opts = opts or {}
	vim.cmd.tabnew()
	local win = Markup.window({ position = "current", show = false, minimal = true })
	win.buf = api.nvim_get_current_buf()
	win:show()
	vim.bo[win.buf].buftype = "nofile"
	vim.bo[win.buf].bufhidden = "wipe"

	paused(false)
	capped(false)
	M.apply_preset(opts.preset or "medium")
	if Markup.animate.fps ~= math.huge then
		fps = Markup.animate.fps
	end
	Markup.animate.set_fps(math.huge)
	local view = Markup.view(win)
	view:render(Stress())

	-- However the tab goes away, other views get their usual rate back.
	api.nvim_create_autocmd("BufWipeout", {
		buffer = win.buf,
		once = true,
		callback = function()
			M.close_settings()
			if Markup.animate.fps == math.huge then
				Markup.animate.set_fps(fps)
			end
		end,
	})

	local tab = api.nvim_get_current_tabpage()
	local function close()
		M.close_settings()
		-- A rate picked in the inspector while it ran is kept.
		if Markup.animate.fps == math.huge then
			Markup.animate.set_fps(fps)
		end
		local inspector = Markup.devkit.tree().get(view)
		if inspector then
			inspector:close()
		end
		view:destroy()
		if api.nvim_tabpage_is_valid(tab) and #api.nvim_list_tabpages() > 1 then
			vim.cmd.tabclose(api.nvim_tabpage_get_number(tab))
		end
	end

	local function cycle(by)
		local current = M.preset()
		local index = 3
		for i, preset in ipairs(M.presets) do
			if preset.name == current then
				index = i
			end
		end
		index = math.max(math.min(index + by, #M.presets), 1)
		M.apply_preset(M.presets[index].name)
	end

	win:map("n", "q", close)
	win:map("n", "s", function()
		open_settings(view)
	end)
	win:map("n", "<Space>", function()
		paused(not paused())
	end)
	win:map("n", "t", function()
		capped(not capped())
		Markup.animate.set_fps(capped() and fps or math.huge)
	end)
	win:map("n", "+", function()
		cycle(1)
	end)
	win:map("n", "-", function()
		cycle(-1)
	end)

	api.nvim_set_current_win(win.win)
	Markup.devkit.tree().toggle(view)
	api.nvim_set_current_win(win.win)
	if opts.settings then
		open_settings(view)
	end
	return view
end

return M
