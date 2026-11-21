---@module 'mini.test'

-- The colors a user sees, cell by cell, read through a real UI attached to the
-- child (tests/helpers/screen.lua). Unlike extmarks, this is what Neovim drew
-- after everything that changes a color: groups, links, namespaces, floats,
-- `winblend` and the backdrop. The same on every version of Neovim.

local new_set = MiniTest.new_set
local eq = MiniTest.expect.equality
local child = MiniTest.new_child_neovim()
local Screen = dofile("tests/helpers/screen.lua")
---@type tests.Screen
local screen

-- The palette every case draws with.
local FG, BG = "#cdd6f4", "#1e1e2e"
local FLOAT_BG = "#181825"
-- A view's window draws with `NormalFloat`, through `MarkupNormal`.
local VIEW_BG = FLOAT_BG
local LABEL = "#89b4fa"
local CARD = "#313244"
local SPECIAL = "#f38ba8"
local LINE = "#45475a"

local T = new_set({
	hooks = {
		pre_case = function()
			child.restart({ "-u", "scripts/minimal_init.lua" })
			child.o.lines, child.o.columns = 16, 50
			child.lua(([[
				vim.o.termguicolors = true
				vim.o.laststatus = 0
				vim.o.ruler = false
				vim.o.showmode = false
				vim.api.nvim_set_hl(0, "Normal", { fg = %q, bg = %q })
				vim.api.nvim_set_hl(0, "NormalFloat", { fg = %q, bg = %q })
				vim.api.nvim_set_hl(0, "FloatBorder", { fg = %q, bg = %q })
				vim.api.nvim_set_hl(0, "Label", { fg = %q })
				vim.api.nvim_set_hl(0, "Card", { bg = %q })
				vim.api.nvim_set_hl(0, "Special", { fg = %q })
				vim.api.nvim_set_hl(0, "CursorLine", { bg = %q })
				vim.api.nvim_set_hl(0, "EndOfBuffer", { fg = %q })
				m = require("markup")
				reactive = require("markup.reactive")
				function current_view()
					win = Markup.window({ position = "current", hijack = true, show = false, minimal = false })
					win.buf = vim.api.nvim_get_current_buf()
					win:show()
					view = Markup.view(win)
				end
			]]):format(FG, BG, FG, FLOAT_BG, FG, FLOAT_BG, LABEL, CARD, SPECIAL, LINE, BG))
			screen = Screen.attach(child)
		end,
		post_case = function()
			screen:detach()
		end,
		post_once = function()
			child.stop()
		end,
	},
})

local function run(code)
	child.lua(code)
	child.lua("reactive.flush()")
	screen:update(child)
end

--- Each channel of a color times `factor`, the way the dimming computes it.
local function scale(color, factor)
	local n = tonumber(color:sub(2), 16)
	local r, g, b = math.floor(n / 65536), math.floor(n / 256) % 256, n % 256
	return ("#%02x%02x%02x"):format(
		math.floor(r * factor),
		math.floor(g * factor),
		math.floor(b * factor)
	)
end

--- How far apart two colors are, the largest difference of a channel.
local function distance(a, b)
	local x, y = tonumber(a:sub(2), 16), tonumber(b:sub(2), 16)
	local most = 0
	for shift = 0, 2 do
		local d = 256 ^ shift
		most = math.max(most, math.abs(math.floor(x / d) % 256 - math.floor(y / d) % 256))
	end
	return most
end

--- Within a step of rounding of `expected`, as blending in Neovim rounds.
local function near(actual, expected)
	if actual == nil or distance(actual, expected) > 2 then
		error(("expected a color near %s, got %s"):format(expected, tostring(actual)), 2)
	end
end

T["view"] = new_set({
	hooks = {
		pre_case = function()
			child.lua("current_view()")
		end,
	},
})

T["view"]["draws text in the window's colors"] = function()
	run([[view:render(m.block("plain"))]])
	eq(screen:spans(1, 1, 6), { { "plain ", fg = FG, bg = VIEW_BG } })
end

T["view"]["colors only the text of a highlighted inline"] = function()
	run([[view:render(m.block({ m.inline("a "), m.inline("label", "Label"), m.inline(" b") }))]])
	eq(screen:spans(1, 1, 10), {
		{ "a ", fg = FG, bg = VIEW_BG },
		{ "label", fg = LABEL, bg = VIEW_BG },
		{ " b ", fg = FG, bg = VIEW_BG },
	})
end

T["view"]["draws a style table in its colors"] = function()
	run([[view:render(m.inline("red", { fg = "#ff0000", bg = "#000080", bold = true }))]])
	eq(screen:cell_at("red"), { text = "r", fg = "#ff0000", bg = "#000080", bold = true })
end

T["view"]["fills the whole box of a block with its background"] = function()
	run(
		[[view:render(m.block({ m.block({ "ab", width = 8, padding = { 1, 2 }, style = "Card" }), m.block("after") }))]]
	)
	-- `width` is of the content, the padding goes around it. The padding rows
	-- and the cells past the text, all in the card's background.
	for row = 1, 3 do
		eq(screen:spans(row, 1, 12), { { screen:line(row):sub(1, 12), fg = FG, bg = CARD } })
	end
	eq(screen:line(2):sub(1, 12), "  ab        ")
	eq(screen:cell(1, 13).bg, VIEW_BG)
	eq(screen:spans(4, 1, 5), { { "after", fg = FG, bg = VIEW_BG } })
end

T["view"]["keeps the parent's background under a child's foreground"] = function()
	run(
		[[view:render(m.block({ width = 10, style = "Card", m.inline("x", "Label"), m.inline("y") }))]]
	)
	eq(screen:cell_at("x"), { text = "x", fg = LABEL, bg = CARD })
	eq(screen:cell_at("y"), { text = "y", fg = FG, bg = CARD })
end

T["view"]["changes the color with a dynamic style"] = function()
	run([[
		color = m.signal("Label")
		view:render(m.inline({ "word", style = color }))
	]])
	eq(screen:cell_at("word").fg, LABEL)
	run([[color("Special")]])
	eq(screen:cell_at("word").fg, SPECIAL)
end

T["view"]["follows a colorscheme change"] = function()
	run([[view:render(m.inline("word", "Label"))]])
	run([[
		vim.api.nvim_set_hl(0, "Label", { fg = "#00ff00" })
		vim.api.nvim_exec_autocmds("ColorScheme", {})
	]])
	eq(screen:cell_at("word").fg, "#00ff00")
end

T["view"]["draws a border in its style"] = function()
	run(
		[[view:render(m.block({ m.block({ "in", width = 6, border = "single", border_style = "Label" }) }))]]
	)
	-- Around the content, which is 6 wide.
	eq(screen:spans(1, 1, 8), { { "┌──────┐", fg = LABEL, bg = VIEW_BG } })
	eq(screen:cell(2, 1), { text = "│", fg = LABEL, bg = VIEW_BG })
	eq(screen:cell_at("in"), { text = "i", fg = FG, bg = VIEW_BG })
end

T["view"]["draws a half border in the card's color over the window's"] = function()
	run([[view:render(m.block({ m.block({ "ab", width = 4, style = "Card", border = "half" }) }))]])
	-- Half blocks: the card's color in front, the window's behind, so the
	-- card ends half a row above and below its text.
	eq(screen:cell(1, 1), { text = "▄", fg = CARD, bg = VIEW_BG })
	eq(screen:cell(3, 1), { text = "▀", fg = CARD, bg = VIEW_BG })
	eq(screen:cell_at("ab").bg, CARD)
end

T["view"]["a half border follows a style that changes"] = function()
	run([[
		lit = m.signal(false)
		view:render(m.block({ m.block({
			"ab",
			width = 4,
			border = "half",
			style = function() return lit() and "CursorLine" or "Card" end,
		}) }))
	]])
	eq(screen:cell(1, 1), { text = "▄", fg = CARD, bg = VIEW_BG })

	run("lit(true)")
	-- The edges in the color the element has now, not the one it started with.
	eq(screen:cell(1, 1), { text = "▄", fg = LINE, bg = VIEW_BG })
	eq(screen:cell(3, 1), { text = "▀", fg = LINE, bg = VIEW_BG })
	eq(screen:cell_at("ab").bg, LINE)
end

T["view"]["colors wide characters across both of their cells"] = function()
	run([[view:render(m.block({ m.inline("你好", "Label"), m.inline("x") }))]])
	local spans = screen:spans(1, 1, 6)
	eq(spans[1], { "你好", fg = LABEL, bg = VIEW_BG })
	-- 你 and 好 take two cells each: "x" and one more fill the six.
	eq(spans[2], { "x ", fg = FG, bg = VIEW_BG })
end

T["view"]["draws a fixed element in a float of its colors"] = function()
	run([[view:render(m.block({
		m.block({ "pinned", position = "fixed", style = "Card", width = 12 }),
		m.block("body"),
	}))]])
	eq(screen:cell_at("pinned"), { text = "p", fg = FG, bg = CARD })
	eq(screen:cell_at("body"), { text = "b", fg = FG, bg = VIEW_BG })
end

T["window"] = new_set()

local function popup(opts)
	run(
		("popup = Markup.window(vim.tbl_extend('force', { width = 20, height = 3, enter = true, text = { 'inside' } }, %s))"):format(
			vim.inspect(opts or {})
		)
	)
end

T["window"]["draws a popup in the float's colors"] = function()
	popup()
	eq(screen:cell_at("inside"), { text = "i", fg = FG, bg = FLOAT_BG })
end

T["window"]["dims what is under a popup, and leaves the popup as it is"] = function()
	run([[vim.api.nvim_buf_set_lines(0, 0, -1, false, { "under the popup" })]])
	local before = screen:cell_at("under")
	eq(before, { text = "u", fg = FG, bg = BG })

	popup({ dim = true })
	-- A 60% backdrop of black: the text and its background lose 40%.
	local after = screen:cell_at("under")
	near(after.fg, scale(FG, 0.6))
	near(after.bg, scale(BG, 0.6))
	eq(screen:cell_at("inside"), { text = "i", fg = FG, bg = FLOAT_BG })

	run("popup:close()")
	eq(screen:cell_at("under"), before)
end

T["window"]["dims as much as `dim` says"] = function()
	run([[vim.api.nvim_buf_set_lines(0, 0, -1, false, { "under" })]])
	popup({ dim = 0.25 })
	near(screen:cell_at("under").fg, scale(FG, 0.75))
end

T["window"]["dims a float under a popup as much as the editor"] = function()
	run([[
		vim.api.nvim_buf_set_lines(0, 0, -1, false, { "editor" })
		local buf = vim.api.nvim_create_buf(false, true)
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "lower float" })
		lower = vim.api.nvim_open_win(buf, false, {
			relative = "editor", row = 10, col = 2, width = 20, height = 1, zindex = 40,
		})
	]])
	eq(screen:cell_at("lower"), { text = "l", fg = FG, bg = FLOAT_BG })

	popup({ dim = true, row = 2 })
	near(screen:cell_at("lower").fg, scale(FG, 0.6))
	near(screen:cell_at("lower").bg, scale(FLOAT_BG, 0.6))
	near(screen:cell_at("editor").fg, scale(FG, 0.6))

	run("popup:close()")
	eq(screen:cell_at("lower"), { text = "l", fg = FG, bg = FLOAT_BG })
end

T["window"]["dims a popup under a newer one, and gives it back in order"] = function()
	run([[vim.api.nvim_buf_set_lines(0, 0, -1, false, { "editor" })]])
	run(
		[[first = Markup.window({ width = 30, height = 3, row = 8, enter = true, dim = true, text = { "first" } })]]
	)
	eq(screen:cell_at("first").fg, FG)
	run(
		[[second = Markup.window({ width = 20, height = 3, row = 2, enter = true, dim = true, text = { "second" } })]]
	)
	near(screen:cell_at("first").fg, scale(FG, 0.6))
	eq(screen:cell_at("second").fg, FG)

	run("second:close()")
	eq(screen:cell_at("first").fg, FG)
	near(screen:cell_at("editor").fg, scale(FG, 0.6))

	run("first:close()")
	eq(screen:cell_at("editor"), { text = "e", fg = FG, bg = BG })
end

T["window"]["dims text on a transparent background, and keeps it transparent"] = function()
	run([[
		vim.api.nvim_set_hl(0, "Normal", { fg = "#cdd6f4" })
		vim.api.nvim_exec_autocmds("ColorScheme", {})
		vim.api.nvim_buf_set_lines(0, 0, -1, false, { "under" })
	]])
	eq(screen:cell_at("under").bg, nil)

	popup({ dim = true })
	local after = screen:cell_at("under")
	near(after.fg, scale(FG, 0.6))
	-- Nothing laid over it: what the terminal shows behind stays.
	eq(after.bg, nil)

	run("popup:close()")
	eq(screen:cell_at("under").fg, FG)
end

T["picker"] = new_set({
	hooks = {
		pre_case = function()
			child.lua([[
				local items = {}
				for i, name in ipairs({ "Two Sum", "Add Two Numbers", "Three Sum" }) do
					items[i] = { label = name, value = i }
				end
				Markup.picker({ title = "Pick", items = items, on_select = function() end })
				reactive.flush()
			]])
			screen:update(child)
		end,
	},
})

T["picker"]["colors what matched the query"] = function()
	child.type_keys("thr")
	run("")
	local row, col = screen:find("Three")
	assert(row, "Three is not on the screen")
	---@cast col integer
	-- "Th" and "r" matched, "ee" did not.
	eq(screen:cell(row, col).fg, SPECIAL)
	eq(screen:cell(row, col + 1).fg, SPECIAL)
	eq(screen:cell(row, col + 2).fg, SPECIAL)
	eq(screen:cell(row, col + 3).fg ~= SPECIAL, true)
end

T["picker"]["marks the selected row with the cursor line's background"] = function()
	local row, col = screen:find("Two Sum")
	assert(row, "Two Sum is not on the screen")
	---@cast col integer
	eq(screen:cell(row, col).bg, LINE)
	local other = screen:find("Three Sum")
	---@cast other integer
	eq(screen:cell(other, col).bg ~= LINE, true)
end

return T
