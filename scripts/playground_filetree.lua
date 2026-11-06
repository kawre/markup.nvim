-- markup.nvim file tree stress test
--
-- A generated tree with fixed contents, so runs can be compared.
-- Live stats are in the winbar. Move into the preview with <C-w>j, then:
--
--   <CR> o l  toggle or expand        h    collapse, or jump to parent
--   E         expand everything       C    collapse everything
--   m         toggle memoized rows    b    run the benchmark
--   + / -     double or halve nodes

local m = require("markup")
local hooks = m.hooks
local preview = Markup.playground.preview
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
	local root = { id = 0, name = "markup-project", dir = true, children = {}, depth = 0, prefix = "" }
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

local tree = {
	root = nil,
	total = 0,
	open = {},
	rows = {},
	memo = false,
	cache = {},
	refresh = function() end,
}

local function reset_tree()
	tree.root, tree.total = generate(NODES)
	tree.open = { [tree.root] = true }
	for _, child in ipairs(tree.root.children) do
		if child.dir then
			tree.open[child] = true
		end
	end
	tree.cache = {}
end

local function collect_rows()
	local rows, n = {}, 0
	local function walk(node)
		n = n + 1
		rows[n] = node
		if node.dir and tree.open[node] then
			for _, child in ipairs(node.children) do
				walk(child)
			end
		end
	end
	walk(tree.root)
	return rows
end

local function build_row(node, width)
	local open = tree.open[node]
	local spans = { key = node.id }
	local left = 0

	local function add(text, group)
		spans[#spans + 1] = m.inline(text, hl(group))
		left = left + vim.fn.strdisplaywidth(text)
	end

	add(" " .. (node.guide or ""), "Guide")
	if node.dir then
		add(open and "▾ " or "▸ ", "Chevron")
		add((open and ICON_DIR_OPEN or ICON_DIR) .. " ", open and "DirOpen" or "Dir")
		add(node.name, open and "DirOpen" or "Dir")
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

	return m.block(spans)
end

local function row_element(node, width)
	if not tree.memo then
		return build_row(node, width)
	end

	local open = tree.open[node] or false
	local entry = tree.cache[node]
	if not entry or entry.open ~= open or entry.width ~= width then
		entry = { open = open, width = width, element = build_row(node, width) }
		tree.cache[node] = entry
	end
	return entry.element
end

local function toggle(node, value)
	if node and node.dir then
		if value == nil then
			value = not tree.open[node]
		end
		tree.open[node] = value or nil
		tree.refresh()
	end
end

local function cursor_node()
	return tree.rows[api.nvim_win_get_cursor(preview.win.win)[1]]
end

local function set_all(open)
	tree.open = { [tree.root] = true }
	if open then
		local function walk(node)
			tree.open[node] = true
			for _, child in ipairs(node.children) do
				if child.dir then
					walk(child)
				end
			end
		end
		walk(tree.root)
	end
	tree.refresh()
end

local function median(values)
	table.sort(values)
	return values[math.ceil(#values / 2)] or 0
end

--- Toggles one directory repeatedly in each state and reports the median frame.
local function benchmark()
	local saved, saved_memo = tree.open, tree.memo
	local target

	--- Picks the smallest directory nearest the middle of the visible rows, so
	--- each toggle is a small change and the row count stays about the same.
	local function pick_target()
		local rows = collect_rows()
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

	local function measure()
		local frames = { reconcile = {}, layout = {}, paint = {}, total = {}, wall = {}, cursor = {} }
		local started = vim.uv.hrtime()
		local i = 0
		target = pick_target()
		tree.refresh()
		preview:rerender()
		local rows_before = #tree.rows
		while i < 15 and (i < 3 or (vim.uv.hrtime() - started) / 1e9 < 4) do
			i = i + 1
			tree.open[target] = not tree.open[target] or nil
			tree.refresh()
			local frame_start = vim.uv.hrtime()
			preview:rerender()
			table.insert(frames.wall, (vim.uv.hrtime() - frame_start) / 1e6)
			local cursor_start = vim.uv.hrtime()
			preview:handle_cursor_moved()
			table.insert(frames.cursor, (vim.uv.hrtime() - cursor_start) / 1e6)
			local stats = preview.stats
			table.insert(frames.reconcile, stats.reconciliation)
			table.insert(frames.layout, stats.layout)
			table.insert(frames.paint, stats.paint)
			table.insert(frames.total, stats.elapsed)
		end
		return {
			rows = rows_before,
			changed = #target.children,
			frames = i,
			reconcile = median(frames.reconcile),
			layout = median(frames.layout),
			paint = median(frames.paint),
			total = median(frames.total),
			wall = median(frames.wall),
			cursor = median(frames.cursor),
		}
	end

	local function open_to_depth(depth)
		tree.open = { [tree.root] = true }
		local function walk(node)
			for _, child in ipairs(node.children) do
				if child.dir and child.depth <= depth then
					tree.open[child] = true
					walk(child)
				end
			end
		end
		walk(tree.root)
	end

	local results = {}
	for _, memo in ipairs({ false, true }) do
		tree.memo = memo
		for _, depth in ipairs({ 1, 2, 3, 12 }) do
			open_to_depth(depth)
			local result = measure()
			result.memo, result.depth = memo, depth
			results[#results + 1] = result
		end
	end

	tree.open, tree.memo = saved, saved_memo
	tree.refresh()

	local lines = { ("file tree benchmark, %d nodes, median ms per toggle"):format(tree.total) }
	lines[#lines + 1] = "memo  depth   rows  +/-rows frames  reconcile  layout    paint     total     wall      cursor"
	for _, r in ipairs(results) do
		lines[#lines + 1] = ("%-5s %-5d %6d  %-7d %-6d %9.2f  %-8.2f  %-8.2f  %-8.2f  %-8.2f  %.2f"):format(
			r.memo and "on" or "off",
			r.depth,
			r.rows,
			r.changed,
			r.frames,
			r.reconcile,
			r.layout,
			r.paint,
			r.total,
			r.wall,
			r.cursor
		)
	end
	_G.MarkupTreeBench = lines
	vim.notify(table.concat(lines, "\n"))
end

local function resize(factor)
	_G.MarkupTreeNodes = math.max(1000, math.floor(NODES * factor))
	vim.cmd("Markup playground run")
end

local bindings = {
	["<CR>"] = function()
		toggle(cursor_node())
	end,
	o = function()
		toggle(cursor_node())
	end,
	l = function()
		toggle(cursor_node(), true)
	end,
	h = function()
		local node = cursor_node()
		if not node then
			return
		end
		if node.dir and tree.open[node] and node.parent then
			toggle(node, false)
		elseif node.parent then
			for row, candidate in ipairs(tree.rows) do
				if candidate == node.parent then
					api.nvim_win_set_cursor(preview.win.win, { row, 0 })
					break
				end
			end
		end
	end,
	E = function()
		set_all(true)
	end,
	C = function()
		set_all(false)
	end,
	m = function()
		tree.memo = not tree.memo
		tree.refresh()
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

local App = m.component(function()
	local version, set_version = hooks.variable(0)
	local win = hooks.window()

	tree.refresh = function()
		set_version(function(v)
			return v + 1
		end)
	end

	hooks.effect(function()
		for lhs, fn in pairs(bindings) do
			win:map("n", lhs, fn)
		end
	end, {})

	local width = api.nvim_win_get_width(win.win)
	local rows = collect_rows()
	tree.rows = rows

	local elements = {}
	for i, node in ipairs(rows) do
		elements[i] = row_element(node, width)
	end

	return m.block(elements), version
end)

local function update_winbar()
	local stats = preview.stats
	if not stats.elapsed or not api.nvim_win_is_valid(preview.win.win) then
		return
	end
	local status = stats.elapsed <= BUDGET and "Good" or stats.elapsed <= BUDGET * 3 and "Warn" or "Bad"
	vim.wo[preview.win.win].winbar = table.concat({
		"%#MarkupTreeBar# ",
		("%d nodes  %d rows  memo %s"):format(tree.total, #tree.rows, tree.memo and "on" or "off"),
		"%#MarkupTreeBarDim#  reconcile ",
		("%.1f  layout %.1f  paint %.1f  "):format(stats.reconciliation, stats.layout, stats.paint),
		"%#MarkupTree" .. status .. "#",
		("%.1f ms"):format(stats.elapsed),
		"%#MarkupTreeBarDim#  <CR> toggle  E/C all  m memo  b bench %=",
	})
end

local group = api.nvim_create_augroup("MarkupPlaygroundTree", { clear = true })
api.nvim_create_autocmd("User", {
	group = group,
	pattern = "MarkupRender" .. preview.win.id,
	callback = update_winbar,
})

vim.wo[preview.win.win].cursorline = true
vim.wo[preview.win.win].wrap = false

reset_tree()
preview:render(App)
