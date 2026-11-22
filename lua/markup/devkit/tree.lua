--- Inspector for views, built with markup itself.
---
--- It costs nothing while closed. While open it only asks the engine for nodes
--- under expanded rows, one page at a time, so a tree with hundreds of thousands
--- of nodes stays cheap to look at.
---
--- Three panes share the side of the screen: performance on top, the element
--- tree in the middle and the selected node at the bottom, so stats and details
--- stay in place however far the tree scrolls.
---
--- Keys: <CR> expand or load more, s options, c show groups, f follow the
--- cursor, m mark the selection in the view, r refresh, q close. Moving onto
--- an element scrolls the view to it.

local m = require("markup")
local reactive = require("markup.reactive")
local protocol = require("markup.view.protocol")
local hl = require("markup.view.hl")

local api = vim.api

local PAGE = 100
-- How often the tree and the stats follow the target. Its frames can come by
-- the hundred a second, which the inspector need not, and should not, redraw.
local REFRESH_MS = 250
local MAX_HIGHLIGHT_ROWS = 200
local BUDGET = 1000 / 60
local STATS_HEIGHT = 5
local DETAIL_HEIGHT = 10
local WIDTH = 0.4
local SAMPLES = 120
local TICK_MS = 500
local SPARK = { "▁", "▂", "▃", "▄", "▅", "▆", "▇", "█" }
local PHASES = { "layout", "paint", "diff", "write" }
local BOX_WIDTH = 30

---@class markup.devkit.tree
---@field target markup.view
---@field view markup.view
---@field win markup.window
---@field details_view markup.view
---@field details_win markup.window
---@field stats_view markup.view
---@field stats_win markup.window
---@overload fun(target: markup.view): markup.devkit.tree
local M = Markup.object()

---@type table<markup.view, markup.devkit.tree>
local instances = setmetatable({}, { __mode = "k" })

--- The inspector marking each window, by window.
---@type table<integer, markup.devkit.tree>
local marking = {}

local PARTS = {
	margin = "MarkupInspectorMarkMargin",
	border = "MarkupInspectorMarkBorder",
	padding = "MarkupInspectorMarkPadding",
	content = "MarkupInspectorTarget",
}

local mark_ns = api.nvim_create_namespace("markup_inspector_marks")

--- Draws the mark again with the window, as the target rewrites its lines on
--- every frame: anything placed on them would go with the text it was on.
--- Cells with text take the color of their part, and where a line is too
--- short for the box, blanks of that color fill it out.
api.nvim_set_decoration_provider(mark_ns, {
	on_win = function(_, win)
		local inspector = marking[win]
		if not inspector or not inspector.marks_by_row then
			return false
		end
		inspector.leftcol = api.nvim_win_call(win, function()
			return vim.fn.winsaveview().leftcol
		end)
	end,
	on_line = function(_, win, buf, row)
		local inspector = marking[win]
		local marks = inspector and inspector.marks_by_row and inspector.marks_by_row[row]
		if not marks then
			return
		end
		local line = api.nvim_buf_get_lines(buf, row, row + 1, false)[1] or ""
		local width = vim.fn.strdisplaywidth(line)
		local leftcol = inspector.leftcol or 0
		for _, mark in ipairs(marks) do
			local first, last, group = mark[2], mark[3], PARTS[mark[4]]
			if first < width then
				local start_byte = math.max(vim.fn.virtcol2col(win, row + 1, first + 1) - 1, 0)
				local end_byte = last >= width and #line
					or vim.fn.virtcol2col(win, row + 1, last + 1) - 1
				if end_byte > start_byte then
					api.nvim_buf_set_extmark(buf, mark_ns, row, start_byte, {
						end_col = end_byte,
						hl_group = group,
						priority = 10000,
						ephemeral = true,
					})
				end
			end
			local blank = math.max(first, width, leftcol)
			if last > blank then
				api.nvim_buf_set_extmark(buf, mark_ns, row, 0, {
					virt_text = { { (" "):rep(last - blank), group } },
					virt_text_win_col = blank - leftcol,
					priority = 10000,
					ephemeral = true,
				})
			end
		end
	end,
})

--- Asks for the window to be drawn again, which draws the mark.
local function redraw(win)
	if api.nvim_win_is_valid(win) then
		if api.nvim__redraw then
			api.nvim__redraw({ win = win, valid = false })
		else
			vim.cmd("redraw")
		end
	end
end

--- Winbar text needs the winbar's background, which depends on the colorscheme.
local function apply_colors()
	local function get(name)
		return api.nvim_get_hl(0, { name = name, link = false })
	end

	local bar = get("WinBar")
	local bg = bar.bg or get("StatusLine").bg

	local sources = {
		Text = { "WinBar" },
		Dim = { "Comment" },
		Strong = { "Title", bold = true },
		Good = { "DiagnosticOk", bold = true },
		Warn = { "DiagnosticWarn", bold = true },
		Bad = { "DiagnosticError", bold = true },
	}

	for name, source in pairs(sources) do
		api.nvim_set_hl(
			0,
			"MarkupInspectorBar" .. name,
			{ fg = get(source[1]).fg, bg = bg, bold = source.bold }
		)
	end

	-- The mark in the view, as browser devtools draw it: content, padding,
	-- border and margin each tinted from the color the box model uses for it.
	local normal_bg = get("Normal").bg
	local layers = {
		Target = { "DiagnosticInfo", "Search" },
		MarkPadding = { "DiagnosticOk", "DiffAdd" },
		MarkBorder = { "DiagnosticHint", "DiffText" },
		MarkMargin = { "DiagnosticWarn", "DiffChange" },
	}
	for name, sources in pairs(layers) do
		local fg = get(sources[1]).fg
		local definition = { link = sources[2], default = true }
		if fg and normal_bg then
			local blend = Markup.util.blend(("#%06x"):format(fg), ("#%06x"):format(normal_bg), 0.35)
			definition = { bg = blend, default = true }
		end
		api.nvim_set_hl(0, "MarkupInspector" .. name, definition)
	end

	local links = {
		Selected = "Visual",
		Guide = "NonText",
		Rule = "WinSeparator",
		Label = "Comment",
		Key = "Special",
		Value = "Normal",
		Strong = "Title",
		Good = "DiagnosticOk",
		Warn = "DiagnosticWarn",
		Bad = "DiagnosticError",
		Layout = "DiagnosticInfo",
		Paint = "DiagnosticHint",
		Diff = "DiagnosticWarn",
		Write = "Special",
		Margin = "DiagnosticWarn",
		Padding = "DiagnosticOk",
		Content = "DiagnosticInfo",
		Block = "Function",
		Flex = "Keyword",
		Inline = "Identifier",
		Text = "String",
		Group = "Comment",
	}
	for name, link in pairs(links) do
		api.nvim_set_hl(0, "MarkupInspector" .. name, { link = link, default = true })
	end
end

--- Green within a frame's budget, yellow within three, red past that.
---@param ms number
local function health(ms)
	return ms <= BUDGET and "Good" or ms <= BUDGET * 3 and "Warn" or "Bad"
end

---@param target markup.view
---@return markup.devkit.tree?
function M.toggle(target)
	local instance = instances[target]
	if instance then
		instance:close()
		return nil
	end
	return M(target)
end

---@param target markup.view
---@return markup.devkit.tree?
function M.get(target)
	return instances[target]
end

--- Cuts `text` to `limit` characters, never inside one, which the engine
--- would refuse as invalid UTF-8.
local function short(text, limit)
	if vim.fn.strcharlen(text) > limit then
		return vim.fn.strcharpart(text, 0, limit) .. "…"
	end
	return text
end

--- 372059 reads as 372.1k.
local function compact(value)
	if value >= 1e6 then
		return ("%.1fM"):format(value / 1e6)
	elseif value >= 1e3 then
		return ("%.1fk"):format(value / 1e3)
	end
	return tostring(value)
end

---@param node markup.core.node
local function label_of(node)
	if node.display == "text" then
		return ("%q"):format(short(node.text or "", 40))
	elseif node.display == "contents" then
		return "group"
	end
	return node.display
end

local KIND_GROUPS = {
	text = "MarkupInspectorText",
	contents = "MarkupInspectorGroup",
	inline = "MarkupInspectorInline",
	flex = "MarkupInspectorFlex",
	grid = "MarkupInspectorFlex",
	canvas = "MarkupInspectorFlex",
}

---@param node markup.core.node
local function group_of(node)
	return KIND_GROUPS[node.display] or "MarkupInspectorBlock"
end

---@param node markup.core.node
local function geometry_of(node)
	if not node.x then
		return ""
	end
	return ("%d,%d  %d×%d"):format(node.x, node.y, node.outer_width, node.outer_height)
end

--- Label and value for each row of the details pane.
---@param node? markup.core.node
local function details_of(node)
	if not node then
		return {}
	end

	local function edges(values)
		return table.concat(values, " ")
	end

	local flags = {}
	for _, name in ipairs({ "interactive", "reverse" }) do
		if node[name] then
			flags[#flags + 1] = name
		end
	end

	return {
		{
			"node",
			("#%d %s  parent %s  %d children"):format(
				node.id,
				label_of(node),
				node.parent or "-",
				node.children
			),
		},
		{
			"box",
			node.x and ("%s  content %d×%d"):format(
				geometry_of(node),
				node.content_width,
				node.content_height
			) or "none, children flow into the parent",
		},
		{ "edges", ("margin %s  padding %s"):format(edges(node.margin), edges(node.padding)) },
		{
			"size",
			("%s × %s  spacing %d  %s"):format(
				node.width,
				node.height,
				node.spacing,
				node.position
			),
		},
		{
			"style",
			("%s  %s"):format(
				node.hl ~= 0 and hl.name(node.hl) or "no highlight",
				table.concat(flags, " ")
			),
		},
		{ "text", node.text and ("%q"):format(short(node.text, 60)) or "-" },
	}
end

--- Steps of the frame rate slider, the last one for no cap at all.
M.fps_steps = { 15, 30, 60, 75, 90, 120, 144, 165, 180, 240, math.huge }

--- The steps, with the configured rate among them even when it is none of them.
local function fps_steps()
	local steps = vim.list_slice(M.fps_steps, 1)
	local configured = (Markup.config.user.animate or {}).fps
	if configured and not vim.tbl_contains(steps, configured) then
		steps[#steps + 1] = configured
		table.sort(steps)
	end
	return steps
end
local SLIDER = 18

--- The step closest to `fps`.
local function fps_step(steps, fps)
	local best, distance = 1, math.huge
	for i, step in ipairs(steps) do
		local d = step == math.huge and (fps == math.huge and 0 or math.huge)
			or math.abs(step - fps)
		if d < distance then
			best, distance = i, d
		end
	end
	return best
end

--- What the options popup lists, in order.
---@type { key: string, label: string, desc: string, shortcut?: string, default: boolean }[]
M.options = {
	{
		key = "follow",
		label = "Follow cursor",
		desc = "select the element under the view's cursor",
		shortcut = "f",
		default = true,
	},
	{
		key = "show_groups",
		label = "Show groups",
		desc = "list the nodes components wrap content in",
		shortcut = "c",
		default = false,
	},
	{
		key = "mark",
		label = "Mark selection",
		desc = "highlight the selected element in the view",
		shortcut = "m",
		default = true,
	},
	{
		key = "geometry",
		label = "Geometry",
		desc = "position and size on every row",
		default = true,
	},
	{
		key = "hl_names",
		label = "Highlight names",
		desc = "highlight groups on every row",
		default = true,
	},
	{
		key = "guides",
		label = "Indent guides",
		desc = "lines joining nested elements",
		default = true,
	},
	{
		key = "live",
		label = "Live updates",
		desc = "refresh the tree as the view changes",
		default = true,
	},
	{
		key = "vrr",
		label = "Variable rate",
		desc = "tick only when an animation can change",
		default = true,
		get = function()
			return Markup.animate.vrr
		end,
		set = function(enabled)
			Markup.animate.vrr = enabled
		end,
	},
}

local options_by_key = {}
for _, option in ipairs(M.options) do
	options_by_key[option.key] = option
end

---@param target markup.view
function M:new(target)
	self.target = target
	self.expanded = { [protocol.ROOT] = true }
	self.offsets = {} ---@type table<integer, integer> first child shown per parent
	self.entries = {}
	self.keys_by_handler = {}
	local defaults = Markup.config.user.inspector or {}
	for _, option in ipairs(M.options) do
		if option.get then
			goto continue
		end
		local default = defaults[option.key]
		if default == nil then
			default = option.default
		end
		self[option.key] = default
		::continue::
	end

	self.rows = m.signal({})
	self.selected = m.signal(protocol.ROOT)
	self.details = m.signal({})
	self.node = m.signal(nil) ---@type markup.core.node?
	self.samples = {} ---@type { at: number, ms: number }[] the last frames of the target, oldest first
	-- When each frame of the last second came, oldest at `first`. Separate from
	-- `samples`, which only keeps enough frames for the sparkline.
	self.stamps, self.first, self.last = {}, 1, 0
	self.perf = m.signal(self:measure())

	self.win = Markup.window({
		position = "right",
		relative = "editor",
		width = WIDTH,
		enter = false,
		minimal = true,
	})
	self.stats_win = Markup.window({
		position = "top",
		relative = "win",
		win = self.win.win,
		height = STATS_HEIGHT,
		enter = false,
		minimal = true,
	})
	self.details_win = Markup.window({
		position = "bottom",
		relative = "win",
		win = self.win.win,
		height = DETAIL_HEIGHT,
		enter = false,
		minimal = true,
	})

	-- Opening the other splits redistributes the columns, so size it afterwards.
	api.nvim_win_set_width(self.win.win, math.floor(vim.o.columns * WIDTH))

	self.view = Markup.view(self.win)
	self.view.devtool = true
	self.stats_view = Markup.view(self.stats_win)
	self.stats_view.devtool = true
	self.details_view = Markup.view(self.details_win)
	self.details_view.devtool = true
	vim.wo[self.win.win].cursorline = true
	-- Thin rules between the panes rather than the name of their buffers.
	for _, win in ipairs({ self.stats_win, self.win, self.details_win }) do
		api.nvim_set_option_value(
			"fillchars",
			"stl:─,stlnc:─",
			{ scope = "local", win = win.win }
		)
		api.nvim_set_option_value(
			"statusline",
			"%#MarkupInspectorRule#",
			{ scope = "local", win = win.win }
		)
	end
	vim.wo[self.stats_win.win].winbar = "%#MarkupInspectorBarStrong# \u{f0e4} Performance"
	vim.wo[self.details_win.win].winbar = "%#MarkupInspectorBarStrong# \u{f1b2} Node"

	instances[target] = self

	apply_colors()
	self:bind_keys()
	self:bind_events()
	self:refresh()
	self.view:render(self:tree())
	self.stats_view:render(self:stats())
	self.details_view:render(self:panel())

	-- Frames per second fall back to zero once the target goes quiet, which no
	-- commit would ever tell.
	self.timer = vim.uv.new_timer()
	self.timer:start(
		TICK_MS,
		TICK_MS,
		vim.schedule_wrap(function()
			if instances[self.target] == self then
				self:update_perf()
			end
		end)
	)
end

--- Remembers how long a frame of the target took.
function M:sample()
	local stats = self.target.stats
	local samples = self.samples
	local at = vim.uv.hrtime() / 1e6
	samples[#samples + 1] = { at = at, ms = stats.engine + stats.apply }
	self.last = self.last + 1
	self.stamps[self.last] = at
	self:forget_before(at - 1000)
	if #samples > SAMPLES then
		table.remove(samples, 1)
	end
end

--- Drops the times of frames older than `at`.
function M:forget_before(at)
	local stamps = self.stamps
	while self.first <= self.last and stamps[self.first] < at do
		stamps[self.first] = nil
		self.first = self.first + 1
	end
end

--- Everything the performance pane shows, read now.
function M:measure()
	local target = self.target
	local stats = target.stats
	local counts = reactive.stats()
	local now = vim.uv.hrtime() / 1e6

	self:forget_before(now - 1000)
	local fps = self.last - self.first + 1

	return {
		fps = fps,
		ms = stats.engine + stats.apply,
		layout = stats.layout,
		paint = stats.paint,
		diff = stats.diff,
		write = stats.apply,
		lines = stats.lines,
		nodes = target.engine:node_count(),
		effects = counts.effects,
		scopes = counts.scopes,
		animations = require("markup.animate").count(),
		ticks = self:tick_rate(now),
		memory = collectgarbage("count") / 1024,
		frames = vim.tbl_map(function(sample)
			return sample.ms
		end, self.samples),
	}
end

--- Animation ticks a second over about the last second, read on each update.
function M:tick_rate(now)
	local history = self.tick_history or {}
	self.tick_history = history
	history[#history + 1] = { at = now, ticks = Markup.animate.ticks }
	while #history > 2 and now - history[2].at >= 1000 do
		table.remove(history, 1)
	end
	local first, last = history[1], history[#history]
	local elapsed = last.at - first.at
	if elapsed <= 0 then
		return 0
	end
	return math.floor((last.ticks - first.ticks) / elapsed * 1000 + 0.5)
end

--- Redraws the performance pane when anything it shows has changed.
function M:update_perf()
	local perf = self:measure()
	local old = reactive.untrack(self.perf)
	local key = ("%d %d %.2f %.2f %.2f %.2f %.2f %d %d %d %d %d %.1f %d"):format(
		perf.ticks,
		perf.fps,
		perf.ms,
		perf.layout,
		perf.paint,
		perf.diff,
		perf.write,
		perf.lines,
		perf.nodes,
		perf.effects,
		perf.scopes,
		perf.animations,
		perf.memory,
		#perf.frames
	)
	local last = self.samples[#self.samples]
	key = key .. (last and (" %d"):format(last.at) or "")
	if old and old.key == key then
		return
	end
	perf.key = key
	self.perf(perf)
end

function M:bind_keys()
	local function map(lhs, fn)
		self.win:map("n", lhs, fn)
	end

	local function activate()
		self.view:press()
	end

	map("<CR>", activate)
	map("o", activate)
	map("q", function()
		self:close()
	end)
	map("r", function()
		self:refresh()
	end)
	map("f", function()
		self:set_option("follow", not self.follow)
	end)
	map("m", function()
		self:set_option("mark", not self.mark)
	end)
	map("c", function()
		self:set_option("show_groups", not self.show_groups)
	end)
	map("s", function()
		self:open_options()
	end)
end

function M:bind_events()
	local target = self.target
	self.group =
		api.nvim_create_augroup(("MarkupInspector%d"):format(target.win.id), { clear = true })

	api.nvim_create_autocmd("User", {
		group = self.group,
		pattern = "MarkupViewCommit" .. target.win.id,
		callback = function()
			self:sample()
			self:request_refresh()
		end,
	})

	api.nvim_create_autocmd("CursorMoved", {
		group = self.group,
		buffer = target.win.buf,
		callback = function()
			if self.follow then
				self:follow_cursor()
			end
		end,
	})

	api.nvim_create_autocmd("CursorMoved", {
		group = self.group,
		buffer = self.win.buf,
		callback = function()
			local key = self.keys_by_handler[self.view.handlers[self.view:node_at_cursor()]]
			if type(key) == "number" then
				self:select(key)
				self:scroll_to(key)
			end
		end,
	})

	api.nvim_create_autocmd("ColorScheme", {
		group = self.group,
		callback = apply_colors,
	})

	api.nvim_create_autocmd("WinResized", {
		group = self.group,
		callback = function()
			self:request_refresh()
		end,
	})

	api.nvim_create_autocmd("WinClosed", {
		group = self.group,
		pattern = {
			tostring(self.win.win),
			tostring(self.stats_win.win),
			tostring(self.details_win.win),
			tostring(target.win.win),
		},
		callback = function()
			vim.schedule(function()
				self:close()
			end)
		end,
	})
end

--- Refreshes at most once per `REFRESH_MS`, however often the target commits.
function M:request_refresh()
	if self.refresh_pending or not self.live then
		return
	end
	self.refresh_pending = true
	vim.defer_fn(function()
		self.refresh_pending = false
		if instances[self.target] == self then
			self:refresh()
		end
	end, REFRESH_MS)
end

--- Rows for everything visible, walking only expanded nodes.
function M:collect()
	local engine = self.target.engine
	local rows = {}

	local function add(key, depth, node, kind)
		rows[#rows + 1] = { key = key, depth = depth, node = node, kind = kind }
	end

	local flatten = not self.show_groups

	local function walk(node, depth)
		add(node.id, depth, node, "node")
		if not self.expanded[node.id] or node.children == 0 then
			return
		end

		local id, child_depth = node.id, depth + 1
		local offset = self.offsets[id] or 0
		local nodes = engine:children(id, offset, PAGE, flatten)

		if offset > 0 then
			add("before:" .. id, child_depth, { parent = id, count = offset }, "before")
		end
		for _, child in ipairs(nodes) do
			walk(child, child_depth)
		end
		local remaining = nodes.total - offset - #nodes
		if remaining > 0 then
			add("after:" .. id, child_depth, { parent = id, count = remaining }, "after")
		end
	end

	walk(engine:describe(protocol.ROOT), 0)
	return rows
end

--- Everything a row shows. Each value feeds one signal, so a row only redraws
--- the parts that differ.
---@param row table
---@param expanded boolean
---@param width integer
---@param options markup.devkit.tree
local function row_values(row, expanded, width, options)
	local guide = (options.guides and "│ " or "  "):rep(row.depth)
	local values = { guide = guide, marker = "  ", id = "", hl_name = "", hl_group = false }

	if row.kind == "node" then
		local node = row.node
		values.label, values.group = label_of(node), group_of(node)
		values.id = (" #%d"):format(node.id)
		values.geometry = geometry_of(node)
		if node.children > 0 then
			values.marker = expanded and "▾ " or "▸ "
		end
		if not options.geometry then
			values.geometry = ""
		end
		if node.hl ~= 0 and options.hl_names then
			values.hl_name = " " .. hl.name(node.hl) .. " "
			values.hl_group = hl.name(node.hl)
		end
	else
		local direction = row.kind == "before" and "earlier" or "more"
		values.label = ("··· %s %s"):format(compact(row.node.count), direction)
		values.group = "Comment"
		values.geometry = ""
	end

	local used = values.hl_name ~= "" and 1 or 0
	for _, name in ipairs({ "guide", "marker", "label", "id", "hl_name" }) do
		used = used + vim.fn.strdisplaywidth(values[name])
	end
	local right = vim.fn.strdisplaywidth(values.geometry)

	-- Geometry stays against the right edge, and gives way on narrow windows.
	local gap = width - used - right - 1
	if gap < 1 then
		values.geometry, gap = "", 0
	end
	values.gap = (" "):rep(gap)
	return values
end

local ROW_FIELDS =
	{ "guide", "marker", "label", "group", "id", "hl_name", "hl_group", "gap", "geometry" }

--- Updates what changed. Rows only rerun when their own text differs.
function M:refresh()
	local rows = self:collect()
	local width = self.win:win_valid() and api.nvim_win_get_width(self.win.win) or 80

	local live = {}
	for _, row in ipairs(rows) do
		live[row.key] = true
		local values = row_values(row, self.expanded[row.key], width, self)
		local entry = self.entries[row.key]
		if entry then
			entry.row = row
			for _, field in ipairs(ROW_FIELDS) do
				entry[field](values[field])
			end
		else
			entry = { row = row }
			for _, field in ipairs(ROW_FIELDS) do
				entry[field] = m.signal(values[field])
			end
			self.entries[row.key] = entry
		end
	end
	for key in pairs(self.entries) do
		if not live[key] then
			self.entries[key] = nil
		end
	end

	self.rows(rows)

	-- The stats follow their own, slower clock.
	self:update_winbar()
	self:show_selection()
end

--- The tree's title, with the flags, stays put while the tree scrolls.
function M:update_winbar()
	if not self.win:win_valid() then
		return
	end

	local function flag(enabled, name)
		local group = enabled and "Good" or "Dim"
		return ("%%#MarkupInspectorBar%s#%s %s "):format(group, enabled and "●" or "○", name)
	end

	local winbar = table.concat({
		"%#MarkupInspectorBarStrong# \u{f0645} Elements ",
		("%%#MarkupInspectorBarDim#%s nodes"):format(compact(self.target.engine:node_count())),
		"%#MarkupInspectorBarText#%<%=",
		flag(self.follow, "follow"),
		flag(self.mark, "mark"),
		flag(self.show_groups, "groups"),
	})
	-- Setting it redraws it, even to the same text.
	if winbar ~= self.winbar then
		self.winbar = winbar
		vim.wo[self.win.win].winbar = winbar
	end
end

--- Shows details for the selected node and marks it in the target.
function M:show_selection()
	local target = self.target
	-- The node may be gone by now, which leaves nothing selected.
	local ok, node = pcall(target.engine.describe, target.engine, reactive.untrack(self.selected))
	node = ok and node or nil

	-- Only what changed is drawn again: a fresh table each time would redraw the
	-- details pane, however often the target commits.
	if not vim.deep_equal(node, reactive.untrack(self.node)) then
		self.details(details_of(node))
		self.node(node)
	end

	if not api.nvim_buf_is_valid(target.win.buf) then
		return
	end
	local marks = (self.mark and node and node.x and target.win:valid()) and self:marks_of(node)
		or {}
	if vim.deep_equal(marks, self.marks) then
		return
	end
	self:clear_marks()
	if #marks == 0 then
		return
	end

	self.marks = marks
	self.marks_by_row = {}
	for _, mark in ipairs(marks) do
		local row = self.marks_by_row[mark[1]] or {}
		row[#row + 1] = mark
		self.marks_by_row[mark[1]] = row
	end
	self.marked_win = target.win.win
	marking[self.marked_win] = self
	redraw(self.marked_win)
end

function M:clear_marks()
	if self.marked_win and marking[self.marked_win] == self then
		marking[self.marked_win] = nil
		redraw(self.marked_win)
	end
	self.marks, self.marks_by_row, self.marked_win = nil, nil, nil
end

--- What is marked in the target, as `{ row, first_cell, end_cell, part }`
--- from zero, where the part is "margin", "border", "padding" or "content".
---@return [integer, integer, integer, string][]
function M:target_marks()
	return vim.deepcopy(self.marks or {})
end

--- The rows a box covers, as `{ row, first_cell, end_cell }`: all of its
--- width where `inside` does not cover the row, and what is left either side
--- of it where it does.
local function ring(box, inside, part, marks, first_row, last_row)
	for row = math.max(box.top, first_row), math.min(box.bottom, last_row) - 1 do
		local left, right = math.max(box.left, 0), box.right
		local cut = inside
			and inside.right > inside.left
			and row >= inside.top
			and row < inside.bottom
		if cut then
			if inside.left > left then
				marks[#marks + 1] = { row, left, math.max(inside.left, left), part }
			end
			if right > inside.right then
				marks[#marks + 1] = { row, math.max(inside.right, left), right, part }
			end
		elseif right > left then
			marks[#marks + 1] = { row, left, right, part }
		end
	end
end

--- The parts of `node` that are in the buffer: its margin, border, padding
--- and content, each a box inside the one before.
---@param node markup.core.node
---@return [integer, integer, integer, string][]
function M:marks_of(node)
	local buf = self.target.win.buf
	local function box(left, top, right, bottom)
		return { left = left, top = top, right = right, bottom = bottom }
	end
	-- Edges come as `{ top, right, bottom, left }`.
	local function shrink(outer, edges)
		edges = edges or { 0, 0, 0, 0 }
		return box(
			outer.left + edges[4],
			outer.top + edges[1],
			outer.right - edges[2],
			outer.bottom - edges[3]
		)
	end

	local margin = box(node.x, node.y, node.x + node.outer_width, node.y + node.outer_height)
	local border = shrink(margin, node.margin)
	local padding = shrink(border, node.border)
	local content = shrink(padding, node.padding)

	-- A node may reach past the edges of the buffer, such as while it slides in,
	-- so only the part of it that is there is marked.
	local first_row = math.max(node.y, 0)
	local last_row =
		math.min(margin.bottom, node.y + MAX_HIGHLIGHT_ROWS, api.nvim_buf_line_count(buf))

	local marks = {}
	ring(margin, border, "margin", marks, first_row, last_row)
	ring(border, padding, "border", marks, first_row, last_row)
	ring(padding, content, "padding", marks, first_row, last_row)
	ring(content, nil, "content", marks, first_row, last_row)
	table.sort(marks, function(a, b)
		return a[1] < b[1] or (a[1] == b[1] and a[2] < b[2])
	end)
	return marks
end

--- Scrolls the target so all of a node shows, or as much as fits from its
--- top, centered when it has to move at all. The cursor stays in the
--- inspector.
---@param key integer
function M:scroll_to(key)
	local target = self.target
	local ok, node = pcall(target.engine.describe, target.engine, key)
	if not ok or not node.x or not target.win:win_valid() then
		return
	end
	local win = target.win.win
	local height = api.nvim_win_get_height(win)
	local count = api.nvim_buf_line_count(target.win.buf)
	local first = math.min(math.max(node.y, 0), count - 1)
	local last = math.min(node.y + math.max(node.outer_height, 1), count) - 1

	api.nvim_win_call(win, function()
		local view = vim.fn.winsaveview()
		local top, bottom = view.topline - 1, view.topline - 1 + height - 1
		if first >= top and last <= bottom then
			return
		end
		local size = last - first + 1
		local topline = size >= height and first
			or math.max(first - math.floor((height - size) / 2), 0)
		-- The cursor has to stay on screen, so it comes along when it would not.
		local cursor = math.min(math.max(view.lnum - 1, topline), topline + height - 1)
		vim.fn.winrestview({ topline = topline + 1, lnum = cursor + 1 })
	end)
end

---@param key integer
function M:select(key)
	self.selected(key)
	self:show_selection()
end

--- Opens the path to the node under the target's cursor and selects it.
function M:follow_cursor()
	local target = self.target
	if not target.win:valid() or api.nvim_get_current_win() ~= target.win.win then
		return
	end

	local engine = target.engine
	local cursor = api.nvim_win_get_cursor(target.win.win)
	local flatten = not self.show_groups

	local path = {}
	for _, id in ipairs(engine:path_at(cursor[1] - 1, vim.fn.virtcol(".") - 1)) do
		if not flatten or engine:describe(id).display ~= "contents" then
			path[#path + 1] = id
		end
	end

	local deepest = path[#path]
	if not deepest then
		return
	end

	for i, id in ipairs(path) do
		if i < #path then
			self.expanded[id] = true
		end
		if i > 1 then
			local position = engine:child_position(id, flatten) or 0
			local parent = path[i - 1]
			local offset = self.offsets[parent] or 0
			if position < offset or position >= offset + PAGE then
				self.offsets[parent] = math.max(position - math.floor(PAGE / 2), 0)
			end
		end
	end

	self.selected(deepest)
	self:refresh()
	reactive.flush()
	self:reveal(deepest)
end

--- Scrolls the inspector to a row.
function M:reveal(key)
	if not self.win:valid() then
		return
	end
	for index, row in ipairs(reactive.untrack(self.rows)) do
		if row.key == key then
			local line = math.min(index, api.nvim_buf_line_count(self.win.buf))
			api.nvim_win_set_cursor(self.win.win, { line, 0 })
			return
		end
	end
end

---@param row table
function M:activate(row)
	if row.kind == "node" then
		if row.node.children > 0 then
			self.expanded[row.key] = not self.expanded[row.key] or nil
		end
		self:select(row.key)
	elseif row.kind == "after" then
		local parent = row.node.parent
		self.offsets[parent] = (self.offsets[parent] or 0) + PAGE
	else
		local parent = row.node.parent
		self.offsets[parent] = math.max((self.offsets[parent] or 0) - PAGE, 0)
	end
	self:refresh()
end

function M:row(row)
	local key = row.key
	local entry = self.entries[key]

	local function press()
		self:activate(entry.row)
	end
	self.keys_by_handler[press] = key
	m.on_cleanup(function()
		self.keys_by_handler[press] = nil
	end)

	return m.block({
		on_press = press,
		style = function()
			return self.selected() == key and "MarkupInspectorSelected" or nil
		end,
		m.inline(entry.guide, "MarkupInspectorGuide"),
		m.inline(entry.marker, "MarkupInspectorGuide"),
		m.inline({ entry.label, style = entry.group }),
		m.inline(entry.id, "MarkupInspectorLabel"),
		m.inline(function()
			return entry.hl_name() ~= "" and " " or ""
		end),
		m.inline({ entry.hl_name, style = entry.hl_group }),
		m.inline(entry.gap),
		m.inline(entry.geometry, "MarkupInspectorLabel"),
	})
end

function M:tree()
	return m.block({
		white_space = "nowrap",
		m.each(self.rows, function(row)
			return self:row(row())
		end, {
			key = function(row)
				return row.key
			end,
		}),
	})
end

--- Text and its highlight, as the parts of one line.
---@alias markup.devkit.part [string, string?]

---@param parts markup.devkit.part[]
local function line(parts)
	local children = {}
	for i, part in ipairs(parts) do
		children[i] = m.inline(part[1], part[2])
	end
	return m.block(children)
end

local function label(text)
	return { text, "MarkupInspectorLabel" }
end

local function value(text, group)
	return { text, group or "MarkupInspectorValue" }
end

--- Frames per second, the last frame's time and a sparkline of the ones before.
function M:pulse()
	local width = self.stats_win:win_valid() and api.nvim_win_get_width(self.stats_win.win) or 60
	local slots = math.max(width - 40, 8)

	return m.block(function()
		local perf = self.perf()
		local frames = perf.frames
		-- Scaled to the slowest recent frame, so small differences still show.
		local top = 0.01
		for _, ms in ipairs(frames) do
			top = math.max(top, ms)
		end

		local parts = {
			value(("%3d"):format(perf.fps), "MarkupInspectorStrong"),
			label(" fps  "),
			value(("%6.2f"):format(perf.ms), "MarkupInspector" .. health(perf.ms)),
			label(" ms  "),
			value(("%4d"):format(perf.ticks), "MarkupInspectorValue"),
			label(Markup.animate.vrr and " ticks vrr  " or " ticks      "),
		}
		local first = math.max(#frames - slots + 1, 1)
		parts[#parts + 1] = label(("·"):rep(slots - (#frames - first + 1)))
		for i = first, #frames do
			local ms = frames[i]
			local level = math.max(math.ceil(ms / top * #SPARK), 1)
			parts[#parts + 1] = { SPARK[math.min(level, #SPARK)], "MarkupInspector" .. health(ms) }
		end
		return line(parts)
	end)
end

--- One bar, split into how long each phase of the last frame took.
function M:phases()
	local width = self.stats_win:win_valid() and api.nvim_win_get_width(self.stats_win.win) or 60
	local size = math.max(width - 2, 10)

	return {
		m.block(function()
			local perf = self.perf()
			local total = 0
			for _, phase in ipairs(PHASES) do
				total = total + perf[phase]
			end
			if total <= 0 then
				return line({ { ("▄"):rep(size), "MarkupInspectorGuide" } })
			end

			local parts, used = {}, 0
			for i, phase in ipairs(PHASES) do
				local cells = i == #PHASES and size - used
					or math.floor(perf[phase] / total * size + 0.5)
				cells = math.max(math.min(cells, size - used), 0)
				used = used + cells
				parts[i] =
					{ ("▄"):rep(cells), "MarkupInspector" .. phase:gsub("^%l", string.upper) }
			end
			return line(parts)
		end),
		m.block(function()
			local perf = self.perf()
			local parts = {}
			for _, phase in ipairs(PHASES) do
				parts[#parts + 1] = { "● ", "MarkupInspector" .. phase:gsub("^%l", string.upper) }
				parts[#parts + 1] = label(phase .. " ")
				parts[#parts + 1] = value(("%.2f  "):format(perf[phase]))
			end
			return line(parts)
		end),
	}
end

--- Counts of what the target is made of.
function M:totals()
	return m.block(function()
		local perf = self.perf()
		local parts = {}
		local function count(amount, name)
			parts[#parts + 1] = value(amount, "MarkupInspectorStrong")
			parts[#parts + 1] = label(" " .. name .. "  ")
		end
		count(compact(perf.nodes), "nodes")
		count(compact(perf.effects), "effects")
		count(compact(perf.scopes), "scopes")
		count(tostring(perf.animations), "anim")
		count(("%.1f"):format(perf.memory), "MB")
		count(tostring(perf.lines), "lines")
		return line(parts)
	end)
end

function M:stats()
	return m.block({
		white_space = "nowrap",
		padding = { 0, 1 },
		self:pulse(),
		self:phases(),
		self:totals(),
	})
end

--- `value` in the middle of a horizontal edge, as in "╭ margin ── 1 ──╮".
local function edge(open, name, amount, close, width)
	local head = open .. (name ~= "" and (" " .. name .. " ") or "")
	local middle = " " .. amount .. " "
	local left = math.max(
		math.floor((width - vim.fn.strdisplaywidth(middle)) / 2) - vim.fn.strdisplaywidth(head),
		0
	)
	local right = math.max(width - vim.fn.strdisplaywidth(head .. middle .. close) - left, 0)
	return head .. ("─"):rep(left), middle, ("─"):rep(right) .. close
end

local function centered(text, width)
	local left = math.floor((width - vim.fn.strdisplaywidth(text)) / 2)
	return (" "):rep(left) .. text .. (" "):rep(width - vim.fn.strdisplaywidth(text) - left)
end

--- Margin around padding around content, as browser devtools draw it.
---@param node markup.core.node
local function box_model(node)
	local outer, inner = BOX_WIDTH, BOX_WIDTH - 8
	local margin, padding = node.margin, node.padding
	local M_, P_, C_ = "MarkupInspectorMargin", "MarkupInspectorPadding", "MarkupInspectorContent"

	local function pair(parts, group, a, b, c)
		parts[#parts + 1] = { a, group }
		parts[#parts + 1] = { b, "MarkupInspectorValue" }
		parts[#parts + 1] = { c, group }
	end

	local rows = {}

	local top = {}
	pair(top, M_, edge("╭", "margin", margin[1], "╮", outer))
	rows[1] = top

	local inner_top = { { "│   ", M_ } }
	pair(inner_top, P_, edge("╭", "padding", padding[1], "╮", inner))
	inner_top[#inner_top + 1] = { "   │", M_ }
	rows[2] = inner_top

	local content = ("%d × %d"):format(node.content_width, node.content_height)
	rows[3] = {
		{ "│", M_ },
		{ centered(tostring(margin[4]), 3), "MarkupInspectorValue" },
		{ "│", P_ },
		{ centered(tostring(padding[4]), 3), "MarkupInspectorValue" },
		{ centered(content, inner - 8), C_ },
		{ centered(tostring(padding[2]), 3), "MarkupInspectorValue" },
		{ "│", P_ },
		{ centered(tostring(margin[2]), 3), "MarkupInspectorValue" },
		{ "│", M_ },
	}

	local inner_bottom = { { "│   ", M_ } }
	pair(inner_bottom, P_, edge("╰", "", padding[3], "╯", inner))
	inner_bottom[#inner_bottom + 1] = { "   │", M_ }
	rows[4] = inner_bottom

	local bottom = {}
	pair(bottom, M_, edge("╰", "", margin[3], "╯", outer))
	rows[5] = bottom

	return m.block(vim.tbl_map(line, rows))
end

--- Facts beside the box model.
---@param node markup.core.node
local function facts(node)
	local flags = {}
	for _, name in ipairs({ "interactive", "reverse" }) do
		if node[name] then
			flags[#flags + 1] = name
		end
	end
	local rows = {
		{ label("at      "), value(("%d, %d"):format(node.x, node.y)) },
		{ label("size    "), value(("%d × %d"):format(node.outer_width, node.outer_height)) },
		{ label("sizing  "), value(("%s × %s"):format(node.width, node.height)) },
		{ label("flow    "), value(("%s, spacing %d"):format(node.position, node.spacing)) },
		{ label("flags   "), value(#flags > 0 and table.concat(flags, " ") or "-") },
	}
	return m.block(vim.tbl_map(line, rows))
end

function M:panel()
	local hints = { label(" ") }
	for _, hint in ipairs({
		{ "<CR>", "open" },
		{ "s", "options" },
		{ "f", "follow" },
		{ "m", "mark" },
		{ "r", "refresh" },
		{ "q", "close" },
	}) do
		hints[#hints + 1] = { hint[1], "MarkupInspectorKey" }
		hints[#hints + 1] = label((" %s  "):format(hint[2]))
	end

	return m.block({
		white_space = "nowrap",
		m.block(function()
			local node = self.node()
			if not node then
				return m.block({ padding = { 0, 1 }, line({ label("nothing selected") }) })
			end

			local title = {
				{ label_of(node), group_of(node) },
				label((" #%d"):format(node.id)),
			}
			if node.hl ~= 0 then
				title[#title + 1] = { "  " }
				title[#title + 1] = { " " .. hl.name(node.hl) .. " ", hl.name(node.hl) }
			end
			title[#title + 1] =
				label(("  parent %s · %d children"):format(node.parent or "-", node.children))

			local body = node.x and m.flex({ gap = 3, box_model(node), facts(node) })
				or line({ label("no box, its children flow into the parent") })

			return m.block({
				padding = { 0, 1 },
				line(title),
				m.block(""),
				body,
				node.text and line({
					label("text    "),
					value(("%q"):format(short(node.text, 60)), "MarkupInspectorText"),
				}) or m.block(""),
			})
		end),
		line(hints),
	})
end

--- Changes an option and redraws what it affects.
---@param key string
---@param enabled boolean
function M:set_option(key, enabled)
	local option = options_by_key[key]
	if option and option.set then
		option.set(enabled)
	else
		self[key] = enabled
	end
	if self.option_signals then
		self.option_signals[key](enabled)
	end
	self:update_winbar()
	if key == "mark" then
		self:show_selection()
	else
		self:refresh()
	end
end

--- A popup over the tree with every option and whether it is on.
function M:open_options()
	if self.options_win and self.options_win:win_valid() then
		self.options_win:focus()
		return
	end

	self.option_signals = {}
	for _, option in ipairs(M.options) do
		local value = self[option.key]
		if option.get then
			value = option.get()
		end
		self.option_signals[option.key] = m.signal(value)
	end

	local width = math.min(api.nvim_win_get_width(self.win.win) - 4, 52)
	local height = #M.options * 2 + 3
	self.options_win = Markup.window({
		position = "float",
		relative = "win",
		win = self.win.win,
		width = width,
		height = height,
		row = 1,
		col = math.max(math.floor((api.nvim_win_get_width(self.win.win) - width) / 2) - 1, 0),
		border = "rounded",
		title = " Inspector options ",
		title_pos = "center",
		footer = " <CR> toggle  q close ",
		footer_pos = "center",
		enter = true,
		focusable = true,
		minimal = true,
		backdrop = false,
	})
	local win = self.options_win
	self.options_view = Markup.view(win, { snap = true, hide_cursor = true })
	self.options_view.devtool = true

	local rows = {}
	for _, option in ipairs(M.options) do
		local enabled = self.option_signals[option.key]
		local hovered = m.signal(false)
		rows[#rows + 1] = m.block({
			padding = { 0, 1 },
			style = function()
				return hovered() and "MarkupInspectorSelected" or nil
			end,
			on_hover = function(value)
				hovered(value)
			end,
			on_press = function()
				self:set_option(option.key, not reactive.untrack(enabled))
			end,
			m.flex({
				justify = "between",
				m.block({
					m.inline(function()
						return enabled() and "\u{f0132} " or "\u{f0131} "
					end, function()
						return enabled() and "MarkupInspectorGood" or "MarkupInspectorLabel"
					end),
					m.inline(option.label, function()
						return enabled() and "MarkupInspectorStrong" or "MarkupInspectorValue"
					end),
				}),
				m.inline(option.shortcut or "", "MarkupInspectorKey"),
			}),
			m.block({ m.inline("  " .. option.desc, "MarkupInspectorLabel") }),
		})
	end
	local steps = fps_steps()
	local step = m.signal(fps_step(steps, Markup.animate.fps))
	local slider_hovered = m.signal(false)
	local function move(by)
		local index = math.max(math.min(reactive.untrack(step) + by, #steps), 1)
		step(index)
		Markup.animate.set_fps(steps[index])
	end
	local function filled()
		return math.floor((step() - 1) / (#steps - 1) * (SLIDER - 1))
	end

	rows[#rows + 1] = m.block({ "" })
	rows[#rows + 1] = m.block({
		padding = { 0, 1 },
		style = function()
			return slider_hovered() and "MarkupInspectorSelected" or nil
		end,
		on_hover = function(value)
			slider_hovered(value)
		end,
		on_press = function()
			move(reactive.untrack(step) == #steps and 1 - #steps or 1)
		end,
		m.flex({
			justify = "between",
			m.block({
				m.inline("\u{f0e4} ", "MarkupInspectorKey"),
				m.inline("Max fps  ", "MarkupInspectorStrong"),
				m.inline(function()
					return ("━"):rep(filled())
				end, "MarkupInspectorGood"),
				m.inline("●", "MarkupInspectorStrong"),
				m.inline(function()
					return ("─"):rep(SLIDER - 1 - filled())
				end, "MarkupInspectorGuide"),
			}),
			m.inline(function()
				local fps = steps[step()]
				return fps == math.huge and "unlimited" or tostring(fps)
			end, "MarkupInspectorValue"),
		}),
		m.block({
			m.inline("  how often animations move, h / l to change", "MarkupInspectorLabel"),
		}),
	})

	self.options_view:render(m.block({ white_space = "nowrap", rows }))
	self.move_fps = move

	for _, lhs in ipairs({ "h", "<Left>" }) do
		win:map("n", lhs, function()
			if reactive.untrack(slider_hovered) then
				move(-1)
			end
		end)
	end
	for _, lhs in ipairs({ "l", "<Right>" }) do
		win:map("n", lhs, function()
			if reactive.untrack(slider_hovered) then
				move(1)
			end
		end)
	end

	local function close()
		self:close_options()
		if self.win:win_valid() then
			api.nvim_set_current_win(self.win.win)
		end
	end
	win:map("n", "<CR>", function()
		self.options_view:press()
	end)
	win:map("n", "<Space>", function()
		self.options_view:press()
	end)
	win:map("n", "q", close)
	win:map("n", "<Esc>", close)
	win:map("n", "s", close)
	api.nvim_create_autocmd("WinLeave", {
		group = self.group,
		buffer = win.buf,
		once = true,
		callback = function()
			vim.schedule(function()
				self:close_options()
			end)
		end,
	})
end

function M:close_options()
	if self.options_view then
		self.options_view:destroy()
		self.options_view = nil
	end
	if self.options_win and self.options_win:win_valid() then
		self.options_win:close()
	end
	self.options_win, self.option_signals, self.move_fps = nil, nil, nil
end

function M:close()
	if instances[self.target] ~= self then
		return
	end
	instances[self.target] = nil

	api.nvim_del_augroup_by_id(self.group)
	if self.timer and not self.timer:is_closing() then
		self.timer:stop()
		self.timer:close()
	end
	self:clear_marks()

	self:close_options()
	self.view:destroy()
	self.stats_view:destroy()
	self.details_view:destroy()
	for _, win in ipairs({ self.details_win, self.stats_win, self.win }) do
		if win:win_valid() then
			win:close()
		end
	end
end

return M
