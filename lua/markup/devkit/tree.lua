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
--- Keys: <CR> expand or load more, c show groups, f follow the cursor,
--- r refresh, q close.

local m = require("markup")
local reactive = require("markup.reactive")
local protocol = require("markup.view.protocol")
local hl = require("markup.view.hl")

local api = vim.api

local PAGE = 100
local REFRESH_MS = 100
local MAX_HIGHLIGHT_ROWS = 200
local BUDGET = 1000 / 60
local STATS_HEIGHT = 5
local DETAIL_HEIGHT = 10
local WIDTH = 0.4
local SAMPLES = 120
local TICK_MS = 250
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
		api.nvim_set_hl(0, "MarkupInspectorBar" .. name, { fg = get(source[1]).fg, bg = bg, bold = source.bold })
	end

	local links = {
		Target = "Search",
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

local function short(text, limit)
	if #text > limit then
		return text:sub(1, limit) .. "..."
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
		{ "node", ("#%d %s  parent %s  %d children"):format(node.id, label_of(node), node.parent or "-", node.children) },
		{
			"box",
			node.x and ("%s  content %d×%d"):format(geometry_of(node), node.content_width, node.content_height)
				or "none, children flow into the parent",
		},
		{ "edges", ("margin %s  padding %s"):format(edges(node.margin), edges(node.padding)) },
		{ "size", ("%s × %s  spacing %d  %s"):format(node.width, node.height, node.spacing, node.position) },
		{
			"style",
			("%s  %s"):format(node.hl ~= 0 and hl.name(node.hl) or "no highlight", table.concat(flags, " ")),
		},
		{ "text", node.text and ("%q"):format(short(node.text, 60)) or "-" },
	}
end

---@param target markup.view
function M:new(target)
	self.target = target
	self.expanded = { [protocol.ROOT] = true }
	self.offsets = {} ---@type table<integer, integer> first child shown per parent
	self.entries = {}
	self.keys_by_handler = {}
	self.show_groups = false
	self.follow = true

	self.rows = m.signal({})
	self.selected = m.signal(protocol.ROOT)
	self.details = m.signal({})
	self.node = m.signal(nil) ---@type markup.core.node?
	self.samples = {} ---@type { at: number, ms: number }[] the last frames of the target, oldest first
	self.perf = m.signal(self:measure())

	self.ns = api.nvim_create_namespace(("markup_inspector_target_[%s]"):format(target.win.id))
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
		api.nvim_set_option_value("fillchars", "stl:─,stlnc:─", { scope = "local", win = win.win })
		api.nvim_set_option_value("statusline", "%#MarkupInspectorRule#", { scope = "local", win = win.win })
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
	samples[#samples + 1] = { at = vim.uv.hrtime() / 1e6, ms = stats.engine + stats.apply }
	if #samples > SAMPLES then
		table.remove(samples, 1)
	end
end

--- Everything the performance pane shows, read now.
function M:measure()
	local target = self.target
	local stats = target.stats
	local counts = reactive.stats()
	local now = vim.uv.hrtime() / 1e6

	local fps = 0
	for i = #self.samples, 1, -1 do
		if now - self.samples[i].at > 1000 then
			break
		end
		fps = fps + 1
	end

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
		memory = collectgarbage("count") / 1024,
		frames = vim.tbl_map(function(sample)
			return sample.ms
		end, self.samples),
	}
end

--- Redraws the performance pane when anything it shows has changed.
function M:update_perf()
	local perf = self:measure()
	local old = reactive.untrack(self.perf)
	local key = ("%d %.2f %.2f %.2f %.2f %.2f %d %d %d %d %d %.1f %d"):format(
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
		self.follow = not self.follow
		self:refresh()
	end)
	map("c", function()
		self.show_groups = not self.show_groups
		self:refresh()
	end)
end

function M:bind_events()
	local target = self.target
	self.group = api.nvim_create_augroup(("MarkupInspector%d"):format(target.win.id), { clear = true })

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
	if self.refresh_pending then
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
local function row_values(row, expanded, width)
	local guide = ("│ "):rep(row.depth)
	local values = { guide = guide, marker = "  ", id = "", hl_name = "", hl_group = false }

	if row.kind == "node" then
		local node = row.node
		values.label, values.group = label_of(node), group_of(node)
		values.id = (" #%d"):format(node.id)
		values.geometry = geometry_of(node)
		if node.children > 0 then
			values.marker = expanded and "▾ " or "▸ "
		end
		if node.hl ~= 0 then
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

local ROW_FIELDS = { "guide", "marker", "label", "group", "id", "hl_name", "hl_group", "gap", "geometry" }

--- Updates what changed. Rows only rerun when their own text differs.
function M:refresh()
	local rows = self:collect()
	local width = self.win:win_valid() and api.nvim_win_get_width(self.win.win) or 80

	local live = {}
	for _, row in ipairs(rows) do
		live[row.key] = true
		local values = row_values(row, self.expanded[row.key], width)
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

	self:update_perf()
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

	vim.wo[self.win.win].winbar = table.concat({
		"%#MarkupInspectorBarStrong# \u{f0645} Elements ",
		("%%#MarkupInspectorBarDim#%s nodes"):format(compact(self.target.engine:node_count())),
		"%#MarkupInspectorBarText#%<%=",
		flag(self.follow, "follow"),
		flag(self.show_groups, "groups"),
	})
end

--- Shows details for the selected node and marks it in the target.
function M:show_selection()
	local target = self.target
	local ok, node = pcall(target.engine.describe, target.engine, reactive.untrack(self.selected))
	node = ok and node or nil
	self.details(details_of(node))
	self.node(node)

	local buf = target.win.buf
	api.nvim_buf_clear_namespace(buf, self.ns, 0, -1)
	if not node or not node.x or not target.win:valid() then
		return
	end

	local last = math.min(node.y + node.outer_height, node.y + MAX_HIGHLIGHT_ROWS, api.nvim_buf_line_count(buf))
	local win = target.win.win
	-- A node may reach past the edges of the buffer, such as while it slides in,
	-- so only the part of it that is there is marked.
	local left = math.max(node.x, 0)
	local right = node.x + node.outer_width
	for row = math.max(node.y, 0), last - 1 do
		local line = api.nvim_buf_get_lines(buf, row, row + 1, false)[1] or ""
		local width = vim.fn.strdisplaywidth(line)
		if left < width and right > left then
			local start_col = math.max(vim.fn.virtcol2col(win, row + 1, left + 1) - 1, 0)
			local end_col = width <= right and #line or vim.fn.virtcol2col(win, row + 1, right + 1) - 1
			if end_col > start_col then
				pcall(api.nvim_buf_set_extmark, buf, self.ns, row, start_col, {
					end_col = end_col,
					hl_group = "MarkupInspectorTarget",
					priority = 10000,
				})
			end
		end
	end
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
			return self:row(row)
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
	local slots = math.max(width - 26, 8)

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
			label(" ms   "),
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
				local cells = i == #PHASES and size - used or math.floor(perf[phase] / total * size + 0.5)
				cells = math.max(math.min(cells, size - used), 0)
				used = used + cells
				parts[i] = { ("▄"):rep(cells), "MarkupInspector" .. phase:gsub("^%l", string.upper) }
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
	local left = math.max(math.floor((width - vim.fn.strdisplaywidth(middle)) / 2) - vim.fn.strdisplaywidth(head), 0)
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
	for _, hint in ipairs({ { "<CR>", "open" }, { "c", "groups" }, { "f", "follow" }, { "r", "refresh" }, { "q", "close" } }) do
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
			title[#title + 1] = label(("  parent %s · %d children"):format(node.parent or "-", node.children))

			local body = node.x and m.flex({ gap = 3, box_model(node), facts(node) })
				or line({ label("no box, its children flow into the parent") })

			return m.block({
				padding = { 0, 1 },
				line(title),
				m.block(""),
				body,
				node.text and line({ label("text    "), value(("%q"):format(short(node.text, 60)), "MarkupInspectorText") })
					or m.block(""),
			})
		end),
		line(hints),
	})
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
	if api.nvim_buf_is_valid(self.target.win.buf) then
		api.nvim_buf_clear_namespace(self.target.win.buf, self.ns, 0, -1)
	end

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
