--- Inspector for views, built with markup itself.
---
--- It costs nothing while closed. While open it only asks the engine for nodes
--- under expanded rows, one page at a time, so a tree with hundreds of thousands
--- of nodes stays cheap to look at.
---
--- Stats live in the winbar and node details in their own pane, so both stay in
--- place however far the tree scrolls.
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
local DETAIL_HEIGHT = 8
local WIDTH = 0.4
local WIDE_WINBAR = 90
local NARROW_WINBAR = 72

---@class markup.devkit.tree
---@field target markup.view
---@field view markup.view
---@field win markup.window
---@field details_view markup.view
---@field details_win markup.window
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

	api.nvim_set_hl(0, "MarkupInspectorTarget", { link = "Search", default = true })
	api.nvim_set_hl(0, "MarkupInspectorSelected", { link = "Visual", default = true })
	api.nvim_set_hl(0, "MarkupInspectorGuide", { link = "NonText", default = true })
	api.nvim_set_hl(0, "MarkupInspectorLabel", { link = "Comment", default = true })
	api.nvim_set_hl(0, "MarkupInspectorKey", { link = "Special", default = true })
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

---@param node markup.core.node
local function group_of(node)
	if node.display == "text" then
		return "String"
	elseif node.display == "contents" then
		return "Comment"
	end
	return "Function"
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
	self.frame = m.signal("")
	self.details = m.signal({})

	self.ns = api.nvim_create_namespace(("markup_inspector_target_[%s]"):format(target.win.id))
	self.win = Markup.window({
		position = "right",
		relative = "editor",
		width = WIDTH,
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

	-- Opening the second split redistributes the columns, so size it afterwards.
	api.nvim_win_set_width(self.win.win, math.floor(vim.o.columns * WIDTH))

	self.view = Markup.view(self.win)
	self.view.devtool = true
	self.details_view = Markup.view(self.details_win)
	self.details_view.devtool = true
	vim.wo[self.win.win].cursorline = true

	instances[target] = self

	apply_colors()
	self:bind_keys()
	self:bind_events()
	self:refresh()
	self.view:render(self:tree())
	self.details_view:render(self:panel())
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
		pattern = { tostring(self.win.win), tostring(self.details_win.win), tostring(target.win.win) },
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
			values.hl_name = " " .. hl.name(node.hl)
			values.hl_group = hl.name(node.hl)
		end
	else
		local direction = row.kind == "before" and "earlier" or "more"
		values.label = ("··· %s %s"):format(compact(row.node.count), direction)
		values.group = "Comment"
		values.geometry = ""
	end

	local used = 0
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

	local stats = self.target.stats
	self.frame(
		("layout %.2f  paint %.2f  diff %.2f  write %.2f  %d lines"):format(
			stats.layout,
			stats.paint,
			stats.diff,
			stats.apply,
			stats.lines
		)
	)

	self:update_winbar()
	self:show_selection()
end

--- Stats belong in the winbar, because it stays put while the tree scrolls.
function M:update_winbar()
	if not self.win:win_valid() then
		return
	end

	local target = self.target
	local counts = reactive.stats()
	local stats = target.stats
	local total = stats.engine + stats.apply
	local status = total <= BUDGET and "Good" or total <= BUDGET * 3 and "Warn" or "Bad"

	local function stat(value, name)
		return ("%%#MarkupInspectorBarStrong#%s%%#MarkupInspectorBarDim# %s  "):format(compact(value), name)
	end

	local function flag(enabled, name)
		local group = enabled and "Good" or "Dim"
		return ("%%#MarkupInspectorBar%s#%s %s "):format(group, enabled and "●" or "○", name)
	end

	local width = api.nvim_win_get_width(self.win.win)

	local parts = {
		"%#MarkupInspectorBarText# ",
		stat(target.engine:node_count(), "nodes"),
		stat(counts.effects, "effects"),
		width >= NARROW_WINBAR and stat(counts.scopes, "scopes") or "",
		("%%#MarkupInspectorBar%s#%.1f ms "):format(status, total),
	}

	if width >= WIDE_WINBAR then
		parts[#parts + 1] = ("%%#MarkupInspectorBarDim# L %.1f  P %.1f  D %.1f  W %.1f"):format(
			stats.layout,
			stats.paint,
			stats.diff,
			stats.apply
		)
	end

	parts[#parts + 1] = "%#MarkupInspectorBarText#%<%="
	parts[#parts + 1] = flag(self.follow, "follow")
	parts[#parts + 1] = flag(self.show_groups, "groups")

	vim.wo[self.win.win].winbar = table.concat(parts)
end

--- Shows details for the selected node and marks it in the target.
function M:show_selection()
	local target = self.target
	local ok, node = pcall(target.engine.describe, target.engine, reactive.untrack(self.selected))
	node = ok and node or nil
	self.details(details_of(node))

	local buf = target.win.buf
	api.nvim_buf_clear_namespace(buf, self.ns, 0, -1)
	if not node or not node.x or not target.win:valid() then
		return
	end

	local last = math.min(node.y + node.outer_height, node.y + MAX_HIGHLIGHT_ROWS, api.nvim_buf_line_count(buf))
	local win = target.win.win
	for row = node.y, last - 1 do
		local line = api.nvim_buf_get_lines(buf, row, row + 1, false)[1]
		local right = node.x + node.outer_width
		local start_col = vim.fn.virtcol2col(win, row + 1, node.x + 1) - 1
		local end_col = vim.fn.strdisplaywidth(line) <= right and #line
			or vim.fn.virtcol2col(win, row + 1, right + 1) - 1
		if end_col > start_col then
			api.nvim_buf_set_extmark(buf, self.ns, row, start_col, {
				end_col = end_col,
				hl_group = "MarkupInspectorTarget",
				priority = 10000,
			})
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
		m.inline({ entry.hl_name, style = entry.hl_group }),
		m.inline(entry.gap),
		m.inline(entry.geometry, "MarkupInspectorLabel"),
	})
end

function M:tree()
	return m.each(self.rows, function(row)
		return self:row(row)
	end, {
		key = function(row)
			return row.key
		end,
	})
end

--- One aligned row of the details pane.
local function field(label, value)
	return m.block({
		m.inline((" %-6s"):format(label), "MarkupInspectorLabel"),
		m.inline(value),
	})
end

function M:panel()
	local rows = {}
	for i = 1, 6 do
		rows[i] = m.block({
			m.inline(function()
				local detail = self.details()[i]
				return (" %-6s"):format(detail and detail[1] or "")
			end, "MarkupInspectorLabel"),
			m.inline(function()
				local detail = self.details()[i]
				return detail and detail[2] or ""
			end),
		})
	end

	local hints = { " " }
	for _, hint in ipairs({ { "<CR>", "open" }, { "c", "groups" }, { "f", "follow" }, { "r", "refresh" }, { "q", "close" } }) do
		hints[#hints + 1] = m.inline(hint[1], "MarkupInspectorKey")
		hints[#hints + 1] = m.inline((" %s  "):format(hint[2]), "MarkupInspectorLabel")
	end

	return m.block({
		rows,
		field("frame", self.frame),
		m.block(hints),
	})
end

function M:close()
	if instances[self.target] ~= self then
		return
	end
	instances[self.target] = nil

	api.nvim_del_augroup_by_id(self.group)
	if api.nvim_buf_is_valid(self.target.win.buf) then
		api.nvim_buf_clear_namespace(self.target.win.buf, self.ns, 0, -1)
	end

	self.view:destroy()
	self.details_view:destroy()
	for _, win in ipairs({ self.details_win, self.win }) do
		if win:win_valid() then
			win:close()
		end
	end
end

return M
