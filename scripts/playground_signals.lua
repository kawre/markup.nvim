-- markup.nvim file tree on signals and the native engine
--
-- The same generated tree as `playground_filetree.lua`, written the signal way.
-- Each folder owns an `open` signal, so a toggle touches that folder only, and
-- a subtree is not mounted until it is first opened.
--
-- Move into the preview with <C-w>j, then:
--
--   <CR> o l  toggle or expand        h    collapse, or jump to parent
--   E         expand everything       C    collapse everything
--   b         run the benchmark       + / -  double or halve nodes

local m = require("markup")
local reactive = require("markup.reactive")
local view = Markup.playground.preview
local api = vim.api

local NODES = _G.MarkupTreeNodes or 20000
local BUDGET = 1000 / 60

local colors = {
	Guide = "#45475a",
	Dir = { fg = "#89b4fa", bold = true },
	DirOpen = { fg = "#89dceb", bold = true },
	Chevron = "#6c7086",
	File = "#cdd6f4",
	Hidden = "#7f849c",
	Size = "#6c7086",
	Date = "#585b70",
	GitM = { fg = "#f9e2af", bold = true },
	GitA = { fg = "#a6e3a1", bold = true },
	GitU = { fg = "#f38ba8", bold = true },
	Lua = "#74c7ec",
	Rust = "#fab387",
	Ts = "#89b4fa",
	Md = "#a6e3a1",
	Json = "#f9e2af",
	Toml = "#cba6f7",
	Py = "#f9e2af",
	Go = "#89dceb",
	Css = "#f5c2e7",
	Image = "#f2cdcd",
	Good = { fg = "#a6e3a1", bold = true },
	Warn = { fg = "#f9e2af", bold = true },
	Bad = { fg = "#f38ba8", bold = true },
	Bar = { fg = "#cdd6f4", bg = "#313244" },
	BarDim = { fg = "#a6adc8", bg = "#313244" },
}
for name, value in pairs(colors) do
	api.nvim_set_hl(0, "MarkupTree" .. name, type(value) == "string" and { fg = value } or value)
end

local function hl(name)
	return "MarkupTree" .. name
end

local file_types = {
	{ "lua", "\u{e620}", "Lua" },
	{ "rs", "\u{e7a8}", "Rust" },
	{ "ts", "\u{e628}", "Ts" },
	{ "md", "\u{e73e}", "Md" },
	{ "json", "\u{e60b}", "Json" },
	{ "toml", "\u{e615}", "Toml" },
	{ "py", "\u{e73c}", "Py" },
	{ "go", "\u{e626}", "Go" },
	{ "css", "\u{e749}", "Css" },
	{ "png", "\u{f1c5}", "Image" },
}
local ICON_DIR, ICON_DIR_OPEN = "\u{f07b}", "\u{f07c}"
local dir_names = {
	"src", "lib", "core", "utils", "components", "services", "models", "views", "tests", "api",
	"config", "assets", "plugins", "hooks", "store", "layout", "render", "parser", "cache", "docs",
}
local file_names = {
	"index", "init", "main", "types", "config", "helpers", "client", "server", "router", "schema",
	"state", "theme", "button", "input", "table", "tree", "window", "buffer", "events", "logger",
}

-- Park-Miller keeps the generated tree identical between runs.
local seed = 20240
local function rnd(n)
	seed = (seed * 16807) % 2147483647
	return seed % n + 1
end

local function format_size(bytes)
	if bytes >= 1048576 then
		return ("%.1f MB"):format(bytes / 1048576)
	elseif bytes >= 1024 then
		return ("%.1f KB"):format(bytes / 1024)
	end
	return ("%d B"):format(bytes)
end

local function generate(target)
	seed = 20240
	local count = 0
	local root = { id = 0, name = "markup-project", dir = true, children = {}, depth = 0, open = m.signal(true) }
	local queue = { root }
	local head = 1

	while head <= #queue and count < target do
		local dir = queue[head]
		head = head + 1
		local n = dir.depth == 0 and 16 or 6 + rnd(14)
		local used = {}

		for i = 1, n do
			if count >= target then
				break
			end
			count = count + 1
			local is_dir = dir.depth == 0 and i <= 10 or dir.depth < 12 and rnd(100) <= 32
			local node = { id = count, parent = dir, depth = dir.depth + 1, dir = is_dir }

			if is_dir then
				node.name = dir_names[rnd(#dir_names)]
				node.children = {}
				node.open = m.signal(false)
				queue[#queue + 1] = node
			else
				local kind = file_types[rnd(#file_types)]
				node.kind = kind
				node.name = ("%s.%s"):format(file_names[rnd(#file_names)], kind[1])
				node.size = format_size(rnd(4000000))
				local git = rnd(100)
				node.git = git <= 6 and "M" or git <= 9 and "A" or git <= 11 and "U" or nil
			end

			used[node.name] = (used[node.name] or 0) + 1
			if used[node.name] > 1 then
				node.name = ("%s_%d%s"):format(node.name:match("^[^.]+"), i, node.name:match("%.%w+$") or "")
			end
			node.date = ("%02d-%02d"):format(rnd(12), rnd(28))
			dir.children[#dir.children + 1] = node
		end

		table.sort(dir.children, function(a, b)
			if a.dir ~= b.dir then
				return a.dir
			end
			return a.name < b.name
		end)
	end

	local function guides(node)
		for i, child in ipairs(node.children) do
			local last = i == #node.children
			child.guide = (node.child_guide or "") .. (last and "└ " or "├ ")
			child.child_guide = (node.child_guide or "") .. (last and "  " or "│ ")
			if child.dir then
				guides(child)
			end
		end
	end
	guides(root)

	return root, count
end


local root, total = generate(NODES)
for _, child in ipairs(root.children) do
	if child.dir then
		child.open(true)
	end
end

local width = api.nvim_win_get_width(view.win.win)
local nodes_by_handler = {}

local function Entry(node)
	local spans = { m.inline(" " .. (node.guide or ""), hl("Guide")) }
	local left = vim.fn.strdisplaywidth(" " .. (node.guide or ""))

	local function add(text, group)
		spans[#spans + 1] = m.inline(text, hl(group))
		left = left + vim.fn.strdisplaywidth(text)
	end

	if node.dir then
		local open = node.open
		local function group()
			return hl(open() and "DirOpen" or "Dir")
		end

		spans[#spans + 1] = m.inline(function()
			return open() and "▾ " or "▸ "
		end, hl("Chevron"))
		spans[#spans + 1] = m.inline({
			function()
				return (open() and ICON_DIR_OPEN or ICON_DIR) .. " "
			end,
			style = group,
		})
		spans[#spans + 1] = m.inline({ node.name, style = group })
		left = left + 4 + vim.fn.strdisplaywidth(node.name)
		add((" %d"):format(#node.children), "Size")
	else
		add("  ", "Chevron")
		add(node.kind[2] .. " ", node.kind[3])
		add(node.name, node.git and ("Git" .. node.git) or "File")
	end

	local size = node.size or ""
	local right = ("%9s  %5s"):format(size, node.date or "")
	local pad = width - left - #right - 4
	if pad >= 1 then
		add((" "):rep(pad), "File")
		add(node.git and (node.git .. " ") or "  ", node.git and ("Git" .. node.git) or "File")
		add(("%9s  "):format(size), "Size")
		add(node.date or "", "Date")
	end

	local function press()
		if node.dir then
			node.open(function(value)
				return not value
			end)
		end
	end
	nodes_by_handler[press] = node
	spans.on_press = press

	if not node.dir then
		return m.block(spans)
	end

	return {
		m.block(spans),
		m.show(node.open, function()
			local children = {}
			for i, child in ipairs(node.children) do
				children[i] = Entry(child)
			end
			return children
		end),
	}
end

local function cursor_node()
	return nodes_by_handler[view.handlers[view:node_at_cursor()]]
end

local function each_dir(fn)
	local function walk(node)
		fn(node)
		for _, child in ipairs(node.children) do
			if child.dir then
				walk(child)
			end
		end
	end
	walk(root)
end

local function median(values)
	table.sort(values)
	return values[math.ceil(#values / 2)] or 0
end

local function visible_rows()
	return api.nvim_buf_line_count(view.win.buf)
end

--- Toggles a small folder near the middle of what is visible, at each depth.
local function benchmark()
	local function open_to_depth(depth)
		each_dir(function(node)
			node.open(node.depth < depth or node == root)
		end)
		reactive.flush()
	end

	local function pick_target()
		local rows = {}
		local function walk(node)
			rows[#rows + 1] = node
			if node.dir and reactive.untrack(node.open) then
				for _, child in ipairs(node.children) do
					walk(child)
				end
			end
		end
		walk(root)

		local best, best_score
		for i, node in ipairs(rows) do
			if node.dir and node.parent and #node.children > 0 then
				local score = #node.children * 20 + math.abs(i - #rows / 2)
				if not best or score < best_score then
					best, best_score = node, score
				end
			end
		end
		return best
	end

	local results = {}
	for _, depth in ipairs({ 1, 2, 3, 12 }) do
		open_to_depth(depth)
		local target = pick_target()
		local rows = visible_rows()
		local wall, layout, paint, diff, engine, apply, lines, cursor = {}, {}, {}, {}, {}, {}, {}, {}

		for i = 1, 31 do
			target.open(function(value)
				return not value
			end)
			local started = vim.uv.hrtime()
			reactive.flush()
			wall[i] = (vim.uv.hrtime() - started) / 1e6

			local stats = view.stats
			layout[i], paint[i], diff[i] = stats.layout, stats.paint, stats.diff
			engine[i], apply[i], lines[i] = stats.engine, stats.apply, stats.lines

			started = vim.uv.hrtime()
			view.engine:node_at(math.floor(rows / 2), 4)
			cursor[i] = (vim.uv.hrtime() - started) / 1e6
		end

		local total_wall = median(wall)
		local total_engine = median(engine)
		local total_apply = median(apply)
		results[#results + 1] = {
			depth = depth,
			rows = rows,
			changed = #target.children,
			lua = math.max(total_wall - total_engine - total_apply, 0),
			layout = median(layout),
			paint = median(paint),
			diff = median(diff),
			engine = total_engine,
			apply = total_apply,
			total = total_wall,
			cursor = median(cursor),
			lines = median(lines),
		}
	end

	open_to_depth(1)

	local report = { ("signal file tree benchmark, %d nodes, median ms per toggle"):format(total) }
	report[#report + 1] = "depth   rows  +/-rows lua     layout  paint   diff    engine  apply   total    cursor  lines"
	for _, r in ipairs(results) do
		report[#report + 1] = ("%-5d %6d  %-7d %-7.2f %-7.2f %-7.2f %-7.2f %-7.2f %-7.2f %-8.2f %-7.3f %d"):format(
			r.depth,
			r.rows,
			r.changed,
			r.lua,
			r.layout,
			r.paint,
			r.diff,
			r.engine,
			r.apply,
			r.total,
			r.cursor,
			r.lines
		)
	end
	_G.MarkupTreeBench = report
	vim.notify(table.concat(report, "\n"))
end

local function resize(factor)
	_G.MarkupTreeNodes = math.max(1000, math.floor(NODES * factor))
	vim.cmd("Markup playground run")
end

local function toggle_cursor()
	view:press()
end

local bindings = {
	["<CR>"] = toggle_cursor,
	o = toggle_cursor,
	l = function()
		local node = cursor_node()
		if node and node.dir then
			node.open(true)
		end
	end,
	h = function()
		local node = cursor_node()
		if not node then
			return
		end
		if node.dir and reactive.untrack(node.open) and node.parent then
			node.open(false)
		elseif node.parent then
			vim.fn.search("\\V" .. vim.fn.escape(node.parent.name, "\\"), "bW")
		end
	end,
	E = function()
		each_dir(function(node)
			node.open(true)
		end)
	end,
	C = function()
		each_dir(function(node)
			node.open(node == root)
		end)
	end,
	b = function()
		vim.schedule(benchmark)
	end,
	["+"] = function()
		resize(2)
	end,
	["-"] = function()
		resize(0.5)
	end,
}

for lhs, fn in pairs(bindings) do
	view.win:map("n", lhs, fn)
end

local function update_winbar()
	if not api.nvim_win_is_valid(view.win.win) then
		return
	end
	local stats = view.stats
	local elapsed = stats.engine + stats.apply
	local status = elapsed <= BUDGET and "Good" or elapsed <= BUDGET * 3 and "Warn" or "Bad"
	vim.wo[view.win.win].winbar = table.concat({
		"%#MarkupTreeBar# ",
		("%d nodes  %d rows"):format(total, visible_rows()),
		"%#MarkupTreeBarDim#  layout ",
		("%.1f  paint %.1f  diff %.1f  write %.1f  "):format(stats.layout, stats.paint, stats.diff, stats.apply),
		"%#MarkupTree" .. status .. "#",
		("%.1f ms"):format(elapsed),
		"%#MarkupTreeBarDim#  %d lines  <CR> toggle  E/C all  b bench %=",
	}):gsub("%%d lines", ("%d lines"):format(stats.lines))
end

local group = api.nvim_create_augroup("MarkupPlaygroundSignals", { clear = true })
api.nvim_create_autocmd("User", {
	group = group,
	pattern = "MarkupViewCommit" .. view.win.id,
	callback = update_winbar,
})

vim.wo[view.win.win].cursorline = true
vim.wo[view.win.win].wrap = false

view:render(m.block(Entry(root)))
