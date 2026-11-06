-- markup.nvim layout showcase: flex, grid and absolute positioning.
--
-- Move into the preview with <C-w>j, then:
--
--   p  toggle the popup     s  cycle the justify mode
--   +  add a card           -  remove a card
--   w  toggle wrapping in the text panel

local m = require("markup")
local view = Markup.playground.preview

local modes = { "start", "center", "end", "between", "around", "evenly" }
local mode = m.signal(4)
local popup = m.signal(false)
local cards = m.signal({ 1, 2, 3, 4, 5 })
local white_space = m.signal("normal")

local function Panel(title, content)
	return m.block({
		padding = { 0, 1 },
		style = "CursorLine",
		grow = 1,
		m.block(title, "Title"),
		content,
	})
end

local function Header()
	return m.flex({
		justify = "between",
		padding = { 0, 1 },
		style = "StatusLine",
		m.inline("markup.nvim layouts", "Title"),
		m.inline(function()
			return ("justify: %s"):format(modes[mode()])
		end),
	})
end

local function Justify()
	return Panel(
		"flex row",
		m.flex({
			justify = function()
				return modes[mode()]
			end,
			m.block(" one ", "DiffAdd"),
			m.block(" two ", "DiffChange"),
			m.block(" three ", "DiffDelete"),
		})
	)
end

local function Grow()
	return Panel(
		"flex grow",
		m.flex({
			gap = 1,
			m.block({ " 1 ", grow = 1, style = "DiffAdd" }),
			m.block({ " 2 ", grow = 2, style = "DiffChange" }),
			m.block({ " fixed ", style = "DiffDelete" }),
		})
	)
end

local function Cards()
	return Panel(
		"grid, equal columns",
		m.grid({
			columns = 4,
			gap = { 0, 1 },
			m.each(cards, function(card)
				return m.block(" card " .. card, "DiffText")
			end),
		})
	)
end

local function Dashboard()
	return Panel(
		"grid, spans",
		m.grid({
			columns = { 12, "1fr", "1fr" },
			gap = { 0, 1 },
			m.block({ " sidebar", row_span = 2, style = "DiffChange" }),
			m.block({ " wide", column_span = 2, style = "DiffAdd" }),
			m.block(" a", "DiffText"),
			m.block(" b", "DiffDelete"),
		})
	)
end

local function Paragraph()
	return Panel(
		"wrapped text",
		m.block({
			width = 42,
			white_space = white_space,
			m.inline("Text wraps inside its block, like CSS. ", "Normal"),
			m.inline("A line can break inside any span, ", "String"),
			m.inline("and each highlight follows its own words.", "Function"),
		})
	)
end

local function Popup()
	return m.show(
		popup,
		m.vflex({
			position = "absolute",
			top = 2,
			left = 8,
			width = 34,
			z = 10,
			style = "NormalFloat",
			padding = { 1, 2 },
			gap = 1,
			m.block("Absolute popup", "Title"),
			m.block("It hides what is underneath."),
			m.flex({ justify = "end", m.inline(" close with p ", "Visual") }),
		})
	)
end

local App = m.component(function()
	return m.vflex({
		position = "relative",
		gap = 1,
		Header(),
		Justify(),
		Grow(),
		Cards(),
		Dashboard(),
		Paragraph(),
		Popup(),
	})
end)

local keys = {
	p = function()
		popup(function(value)
			return not value
		end)
	end,
	w = function()
		white_space(function(value)
			return value == "normal" and "nowrap" or "normal"
		end)
	end,
	s = function()
		mode(function(value)
			return value % #modes + 1
		end)
	end,
	["+"] = function()
		cards(function(list)
			local next_list = vim.deepcopy(list)
			next_list[#next_list + 1] = #next_list + 1
			return next_list
		end)
	end,
	["-"] = function()
		cards(function(list)
			local next_list = vim.deepcopy(list)
			next_list[#next_list] = nil
			return next_list
		end)
	end,
}

for lhs, fn in pairs(keys) do
	view.win:map("n", lhs, fn)
end

view:render(App())
