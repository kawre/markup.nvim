--- Inspector for views, built with markup itself.
---
--- It costs nothing while closed. While open it only asks the engine for nodes
--- under expanded rows, one page at a time, so a tree with hundreds of thousands
--- of nodes stays cheap to look at.
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
local DETAIL_LINES = 6
local HEADER_LINES = 3 + DETAIL_LINES

---@class markup.devkit.tree
---@field target markup.view
---@field view markup.view
---@field win markup.window
---@overload fun(target: markup.view): markup.devkit.tree
local M = Markup.object()

---@type table<markup.view, markup.devkit.tree>
local instances = setmetatable({}, { __mode = "k" })

vim.api.nvim_set_hl(0, "MarkupInspectorTarget", { link = "Search", default = true })

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

---@param node markup.core.node
local function label_of(node)
	if node.display == "text" then
		return ("%q"):format(short(node.text or "", 40))
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
local function meta_of(node)
	local parts = { (" #%d"):format(node.id) }
	if node.x then
		parts[#parts + 1] = (" %d,%d %dx%d"):format(node.x, node.y, node.outer_width, node.outer_height)
	end
	if node.children > 0 then
		parts[#parts + 1] = (" (%d)"):format(node.children)
	end
	if node.hl ~= 0 then
		parts[#parts + 1] = " " .. hl.name(node.hl)
	end
	return table.concat(parts)
end

---@param node? markup.core.node
local function details_of(node)
	if not node then
		return {}
	end

	local function edges(values)
		return table.concat(values, " ")
	end

	local flags = {}
	for _, name in ipairs({ "interactive", "reverse", "dirty" }) do
		if node[name] then
			flags[#flags + 1] = name
		end
	end

	return {
		("#%d %s  parent %s  children %d"):format(node.id, node.display, node.parent or "-", node.children),
		node.x
				and ("at %d,%d  outer %dx%d  content %dx%d"):format(
					node.x,
					node.y,
					node.outer_width,
					node.outer_height,
					node.content_width,
					node.content_height
				)
			or "no box of its own",
		("margin %s  padding %s"):format(edges(node.margin), edges(node.padding)),
		("width %s  height %s  spacing %d"):format(node.width, node.height, node.spacing),
		("hl %s  %s"):format(node.hl ~= 0 and hl.name(node.hl) or "-", table.concat(flags, " ")),
		node.text and ("text %q"):format(short(node.text, 60)) or "",
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
	self.summary = m.signal("")
	self.frame = m.signal("")
	self.details = m.signal({})

	self.ns = api.nvim_create_namespace(("markup_inspector_target_[%s]"):format(target.win.id))
	self.win = Markup.window({
		position = "right",
		relative = "editor",
		width = 0.4,
		enter = false,
		minimal = true,
	})
	self.view = Markup.view(self.win)
	self.view.devtool = true
	vim.wo[self.win.win].cursorline = true

	instances[target] = self

	self:bind_keys()
	self:bind_events()
	self:refresh()
	self.view:render(self:app())
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

	api.nvim_create_autocmd("WinClosed", {
		group = self.group,
		pattern = { tostring(self.win.win), tostring(target.win.win) },
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

local function row_text(row, expanded)
	local indent = ("  "):rep(row.depth)
	if row.kind == "before" then
		return indent .. "  ", ("... %d earlier"):format(row.node.count), "", "Comment"
	elseif row.kind == "after" then
		return indent .. "  ", ("... %d more"):format(row.node.count), "", "Comment"
	end

	local node = row.node
	local marker = node.children == 0 and "  " or (expanded and "▾ " or "▸ ")
	return indent .. marker, label_of(node), meta_of(node), group_of(node)
end

--- Updates what changed. Rows only rerun when their own text differs.
function M:refresh()
	local target = self.target
	local rows = self:collect()

	local live = {}
	for _, row in ipairs(rows) do
		live[row.key] = true
		local prefix, label, meta, group = row_text(row, self.expanded[row.key])
		local entry = self.entries[row.key]
		if entry then
			entry.row = row
			entry.prefix(prefix)
			entry.label(label)
			entry.meta(meta)
			entry.group(group)
		else
			self.entries[row.key] = {
				row = row,
				prefix = m.signal(prefix),
				label = m.signal(label),
				meta = m.signal(meta),
				group = m.signal(group),
			}
		end
	end
	for key in pairs(self.entries) do
		if not live[key] then
			self.entries[key] = nil
		end
	end

	self.rows(rows)

	local counts = reactive.stats()
	self.summary(
		("nodes %d  effects %d  memos %d  scopes %d  follow %s  groups %s"):format(
			target.engine:node_count(),
			counts.effects,
			counts.memos,
			counts.scopes,
			self.follow and "on" or "off",
			self.show_groups and "on" or "off"
		)
	)

	local stats = target.stats
	self.frame(
		("layout %.2f  paint %.2f  diff %.2f  write %.2f ms  %d lines"):format(
			stats.layout,
			stats.paint,
			stats.diff,
			stats.apply,
			stats.lines
		)
	)

	self:show_selection()
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
			local line = math.min(HEADER_LINES + index, api.nvim_buf_line_count(self.win.buf))
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
			return self.selected() == key and "Visual" or nil
		end,
		m.inline(entry.prefix, "NonText"),
		m.inline({ entry.label, style = entry.group }),
		m.inline(entry.meta, "Comment"),
	})
end

function M:app()
	local details = {}
	for i = 1, DETAIL_LINES do
		details[i] = m.block(function()
			return self.details()[i] or ""
		end)
	end

	return m.block({
		m.block(self.summary, "Title"),
		m.block(self.frame, "Comment"),
		m.newl(),
		details,
		m.each(self.rows, function(row)
			return self:row(row)
		end, {
			key = function(row)
				return row.key
			end,
		}),
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
	if self.win:win_valid() then
		self.win:close()
	end
end

return M
