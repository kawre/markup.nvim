--- Random UIs for property tests, loaded inside the child Neovim.
---
--- A seed makes a spec: a tree of every construct markup has, with some props
--- and children tied to "knobs", signals with a small set of values each.
--- Building the spec reads the knobs, so a fresh view of the same knobs is the
--- oracle for any number of writes to them.

local m = require("markup")
local reactive = require("markup.reactive")

local F = {}

--- Park-Miller, so a seed gives the same run on every machine.
function F.rng(seed)
	local state = seed % 2147483646 + 1
	local r = {}
	function r.int(a, b)
		state = (state * 16807) % 2147483647
		return a + state % (b - a + 1)
	end
	function r.pick(list)
		return list[r.int(1, #list)]
	end
	function r.chance(p)
		return r.int(1, 1000) <= p * 1000
	end
	return r
end

-- Wide characters, a combining accent, an emoji, a tab and nothing at all,
-- next to plain words.
F.WORDS = {
	"a",
	"lorem",
	"ipsum dolor",
	"日本語",
	"e\u{301}te\u{301}",
	"tab\there",
	"",
	"x",
	"averyveryverylongwordthatwillnotfitanywhere",
	"🙂 ok",
	"one two three four five six seven",
}

local STYLES = { "Label", "String", "Comment", { fg = "#ff0000" }, { bg = "#003300", bold = true } }
local LENGTHS = { "auto", "fit", "full", 3, 8, 20 }
local JUSTIFY = { "start", "end", "center", "between", "around", "evenly" }
local ALIGN = { "start", "end", "center", "stretch" }

--- Props a knob can drive, with the values it moves between.
local DYNAMIC = {
	width = LENGTHS,
	padding_left = { 0, 1, 3 },
	margin_top = { 0, 1 },
	justify = JUSTIFY,
	align = ALIGN,
	direction = { "row", "column" },
	white_space = { "normal", "nowrap" },
	style = STYLES,
	overflow_x = { "visible", "hidden" },
	-- Shorthands, which the props docs say take functions as well.
	padding = { 0, 1, { 0, 2 }, { 1, 0, 0, 3 } },
	margin = { 0, { 1, 0 }, { 0, 1, 0, 2 } },
	gap = { 0, 1, { 1, 2 } },
	vertical = { true, false },
	snap = { true, false },
}
-- `pairs` order is not the same from one run to the next, and a seed must be.
local DYNAMIC_NAMES = vim.tbl_keys(DYNAMIC)
table.sort(DYNAMIC_NAMES)

---@param r table rng
---@return table world with `knobs`, `spec` and `build()`
function F.world(r, opts)
	opts = opts or {}
	local knobs = {}

	local function knob(name, domain)
		local signal = m.signal(domain[r.int(1, #domain)])
		knobs[#knobs + 1] = { name = name, domain = domain, signal = signal }
		return #knobs
	end

	local function lists()
		local domain = { {} }
		for _ = 1, 6 do
			local items, seen = {}, {}
			for _ = 1, r.int(1, 6) do
				local key = r.int(1, 7)
				if not seen[key] then
					seen[key], items[#items + 1] = true, key
				end
			end
			domain[#domain + 1] = items
		end
		return domain
	end

	local gen

	local function static_props(tag)
		local props = {}
		if r.chance(0.3) then
			props.padding = r.pick({ 1, { 0, 1 }, { 1, 2, 0, 1 } })
		end
		if r.chance(0.2) then
			props.margin = r.pick({ 1, { 0, 2 } })
		end
		if r.chance(0.3) then
			props.width = r.pick(LENGTHS)
		end
		if r.chance(0.1) then
			props.height = r.int(1, 4)
		end
		if r.chance(0.3) then
			props.style = r.pick(STYLES)
		end
		if r.chance(0.15) then
			props.border = r.pick({ "rounded", "single", "double" })
		end
		if r.chance(0.15) then
			props.white_space = r.pick({ "normal", "nowrap" })
		end
		if r.chance(0.1) then
			props.overflow = "hidden"
		end
		if r.chance(0.1) then
			props.position, props.top, props.left = "relative", r.int(0, 2), r.int(0, 3)
		elseif r.chance(0.05) then
			props.position, props.top, props.left, props.z =
				"absolute", r.int(0, 3), r.int(0, 10), r.int(0, 2)
		end
		if tag == "flex" then
			props.justify = r.chance(0.5) and r.pick(JUSTIFY) or nil
			props.align = r.chance(0.5) and r.pick(ALIGN) or nil
			props.wrap = r.chance(0.3) or nil
			props.vertical = r.chance(0.3) or nil
			props.gap = r.chance(0.3) and r.int(0, 2) or nil
		elseif tag == "grid" then
			props.columns = r.pick({ 2, 3, { "auto", "1fr" }, { 5, "1fr", "auto" } })
			props.gap = r.chance(0.5) and { r.int(0, 1), r.int(0, 2) } or nil
		elseif tag == "block" then
			props.spacing = r.chance(0.2) and 1 or nil
		end
		if r.chance(0.2) then
			props.grow = 1
		end
		return props
	end

	gen = function(depth)
		local roll = r.int(1, 100)
		if depth <= 0 or roll <= 20 then
			if r.chance(0.5) then
				return { kind = "text", value = r.pick(F.WORDS) }
			end
			return { kind = "dyntext", knob = knob("text", F.WORDS) }
		elseif roll <= 30 then
			return {
				kind = "dynchild",
				knob = knob("switch", { true, false }),
				child = gen(depth - 1),
				text = r.pick(F.WORDS),
			}
		elseif roll <= 38 then
			return {
				kind = "show",
				knob = knob("show", { true, false }),
				child = gen(depth - 1),
				fallback = r.chance(0.5) and gen(depth - 1) or nil,
			}
		elseif roll <= 44 and not opts.no_collapse then
			return {
				kind = "collapse",
				knob = knob("collapse", { true, false }),
				child = gen(depth - 1),
			}
		elseif roll <= 52 then
			return { kind = "each", knob = knob("list", lists()), item = gen(depth - 1) }
		elseif roll <= 56 and not opts.no_slide then
			return {
				kind = "slide",
				knob = knob("page", { 1, 2, 3 }),
				pages = { gen(depth - 1), gen(depth - 1), gen(depth - 1) },
			}
		elseif roll <= 60 then
			return { kind = "component", child = gen(depth - 1) }
		end

		local tag = r.pick({ "block", "block", "inline", "flex", "grid" })
		local spec =
			{ kind = "box", tag = tag, props = static_props(tag), dynamic = {}, children = {} }
		for _, name in ipairs(DYNAMIC_NAMES) do
			if r.chance(0.08) then
				spec.dynamic[name] = knob(name, DYNAMIC[name])
			end
		end
		for i = 1, r.int(0, 4) do
			spec.children[i] = gen(depth - 1)
		end
		return spec
	end

	local build

	local function read(index)
		return knobs[index].signal()
	end

	build = function(spec, item)
		local kind = spec.kind
		if kind == "text" then
			return item and (spec.value .. "#" .. item) or spec.value
		elseif kind == "dyntext" then
			return function()
				return read(spec.knob) .. (item and ("#" .. item) or "")
			end
		elseif kind == "dynchild" then
			return function()
				if read(spec.knob) then
					return build(spec.child, item)
				end
				return spec.text
			end
		elseif kind == "show" then
			return m.show(function()
				return read(spec.knob)
			end, function()
				return build(spec.child, item)
			end, spec.fallback and function()
				return build(spec.fallback, item)
			end)
		elseif kind == "collapse" then
			return m.collapse(function()
				return read(spec.knob)
			end, function()
				return m.block({ build(spec.child, item) })
			end)
		elseif kind == "each" then
			return m.block({
				m.each(function()
					return read(spec.knob)
				end, function(item_key)
					local key = item_key()
					return m.block({ "item " .. key .. " ", build(spec.item, key) })
				end),
			})
		elseif kind == "slide" then
			return m.slide(function()
				return read(spec.knob)
			end, function(page)
				return m.block({ "page " .. page, build(spec.pages[page], item) })
			end)
		elseif kind == "component" then
			return m.component(function()
				return build(spec.child, item)
			end)()
		end

		local props = vim.deepcopy(spec.props)
		for name, index in pairs(spec.dynamic) do
			props[name] = function()
				return read(index)
			end
		end
		local children = {}
		for i, child in ipairs(spec.children) do
			children[i] = build(child, item)
		end
		props.children = children
		return m[spec.tag](props)
	end

	local world = { knobs = knobs, writes = {} }
	world.root = {
		kind = "box",
		tag = "block",
		props = {},
		dynamic = {},
		children = { gen(opts.depth or 4), gen(opts.depth or 4) },
	}
	world.columns = vim.o.columns
	world.initial = {}
	for i, entry in ipairs(knobs) do
		world.initial[i] = entry.signal()
	end

	function world.build()
		return build(world.root)
	end

	--- Writes a random value to a random knob, remembering it for a replay.
	--- Now and then the editor is resized instead, which knob 0 stands for.
	function world.mutate()
		if opts.resize and r.chance(0.1) then
			local columns = r.pick(F.COLUMNS)
			world.writes[#world.writes + 1] = { 0, columns }
			F.resize(columns)
			return F.describe_write(world, 0, columns)
		end
		if #knobs == 0 then
			return nil
		end
		local index = r.int(1, #knobs)
		local value = knobs[index].domain[r.int(1, #knobs[index].domain)]
		world.writes[#world.writes + 1] = { index, value }
		knobs[index].signal(value)
		return F.describe_write(world, index, value)
	end

	return world
end

F.COLUMNS = { 24, 41, 60, 90 }

--- Resizes the editor, and with it every window that follows it.
function F.resize(columns)
	vim.o.columns = columns
	vim.api.nvim_exec_autocmds("VimResized", {})
	-- Without a UI Neovim never redraws, so `WinResized` never comes. A frame
	-- is what it would have led to.
	for view in pairs(Markup.views) do
		view:request_commit()
	end
end

function F.describe_write(world, index, value)
	if index == 0 then
		return ("resize to %d columns"):format(value)
	end
	return ("knob %d (%s) = %s"):format(
		index,
		world.knobs[index].name,
		vim.inspect(value, { newline = "", indent = "" })
	)
end

--- Runs pending flushes and the commits they schedule until nothing is left.
function F.settle()
	for _ = 1, 10 do
		reactive.flush()
	end
end

--- Lines, highlights and engine size of a view, as one comparable string.
---@param view markup.view
function F.snapshot(view)
	local marks = vim.tbl_map(function(mark)
		return { mark[2], mark[3], mark[4].end_col, mark[4].hl_group }
	end, vim.api.nvim_buf_get_extmarks(view.win.buf, view.ns, 0, -1, { details = true }))
	table.sort(marks, function(a, b)
		for i = 1, 3 do
			if a[i] ~= b[i] then
				return a[i] < b[i]
			end
		end
		return a[4] < b[4]
	end)
	-- Every box, in tree order: what lays out after updates must be where a
	-- fresh render puts it, even where nothing on screen shows it.
	local boxes = {}
	local engine, limit = view.engine, view.engine:node_count()
	local function visit(id, path)
		for i, node in ipairs(engine:children(id, 0, limit, false)) do
			local at = path .. "/" .. i
			boxes[#boxes + 1] = ("%s %s %d,%d %dx%d"):format(
				at,
				node.display,
				node.x or 0,
				node.y or 0,
				node.outer_width or 0,
				node.outer_height or 0
			)
			if node.children > 0 then
				visit(node.id, at)
			end
		end
	end
	visit(require("markup.view.protocol").ROOT, "")
	return {
		lines = vim.api.nvim_buf_get_lines(view.win.buf, 0, -1, false),
		marks = marks,
		nodes = view.engine:node_count(),
		boxes = boxes,
	}
end

local function live()
	local stats = reactive.stats()
	return { effects = stats.effects, memos = stats.memos, scopes = stats.scopes }
end

--- Renders `content` in a new view as wide as `like`, returning its snapshot
--- and the effects, memos and scopes it keeps alive.
---@param like markup.view
---@param content fun(): any
function F.fresh(like, content)
	local width = vim.api.nvim_win_get_width(like.win.win)
	local win = Markup.window({
		position = "float",
		relative = "editor",
		row = 0,
		col = 0,
		width = width,
		height = 5,
		border = "none",
		backdrop = false,
		enter = false,
		show = true,
	})
	local view = Markup.view(win)
	local before = live()
	view:render(content())
	F.settle()
	local after = live()
	local snapshot = F.snapshot(view)
	view:destroy()
	win:close()
	F.settle()
	return snapshot,
		{
			effects = after.effects - before.effects,
			memos = after.memos - before.memos,
			scopes = after.scopes - before.scopes,
		}
end

--- First difference between two snapshots, or nil.
function F.difference(a, b)
	if a.nodes ~= b.nodes then
		return ("engine holds %d nodes, a fresh render %d"):format(a.nodes, b.nodes)
	end
	for i = 1, math.max(#a.lines, #b.lines) do
		if a.lines[i] ~= b.lines[i] then
			return ("line %d is %s, a fresh render has %s"):format(
				i,
				vim.inspect(a.lines[i]),
				vim.inspect(b.lines[i])
			)
		end
	end
	for i = 1, math.max(#a.boxes, #b.boxes) do
		if a.boxes[i] ~= b.boxes[i] then
			return ("box %s, a fresh render has %s"):format(
				vim.inspect(a.boxes[i]),
				vim.inspect(b.boxes[i])
			)
		end
	end
	for i = 1, math.max(#a.marks, #b.marks) do
		if not vim.deep_equal(a.marks[i], b.marks[i]) then
			return ("highlight %d is %s, a fresh render has %s"):format(
				i,
				vim.inspect(a.marks[i], { newline = "", indent = "" }),
				vim.inspect(b.marks[i], { newline = "", indent = "" })
			)
		end
	end
end

F.live = live

--- Collects errors that effects report through `vim.notify` rather than throw.
F.errors = {}
function F.capture()
	vim.notify = function(message, level)
		if level == vim.log.levels.ERROR then
			F.errors[#F.errors + 1] = message
		end
	end
end

--- Starts the world over from its first knob values, plays `writes` on a new
--- view and returns the first broken property, or nil.
---@param world table
---@param writes table[] `{ knob, value }` pairs
---@param width integer
function F.replay(world, writes, width)
	for i, entry in ipairs(world.knobs) do
		entry.signal(world.initial[i])
	end
	if world.columns then
		F.resize(world.columns)
	end
	F.settle()
	F.errors = {}
	width = world.columns or width

	local win = Markup.window({
		position = "float",
		relative = "editor",
		row = 0,
		col = 0,
		width = width,
		height = 5,
		border = "none",
		backdrop = false,
		enter = false,
	})
	local view = Markup.view(win)
	local base = live()
	local ok, result = pcall(function()
		view:render(world.build())
		F.settle()
		for _, write in ipairs(writes) do
			if write[1] == 0 then
				F.resize(write[2])
				win.opts.width = write[2]
				win:update()
			else
				world.knobs[write[1]].signal(write[2])
			end
			F.settle()
		end
		if #F.errors > 0 then
			return "reported " .. F.errors[1]
		end
		local now = live()
		local fresh, alive = F.fresh(view, world.build)
		local difference = F.difference(F.snapshot(view), fresh)
		if difference then
			return difference
		end
		for _, kind in ipairs({ "effects", "memos", "scopes" }) do
			if now[kind] - base[kind] ~= alive[kind] then
				return ("%d %s alive, a fresh render keeps %d"):format(
					now[kind] - base[kind],
					kind,
					alive[kind]
				)
			end
		end

		-- Taking it all down leaves nothing behind.
		view:unmount()
		F.settle()
		local after = live()
		for _, kind in ipairs({ "effects", "memos", "scopes" }) do
			if after[kind] ~= base[kind] then
				return ("%d %s left after unmount"):format(after[kind] - base[kind], kind)
			end
		end
		if view.engine:node_count() ~= 1 then
			return ("%d engine nodes left after unmount"):format(view.engine:node_count())
		end
	end)
	pcall(view.destroy, view)
	pcall(win.close, win)
	F.settle()
	if not ok then
		return "error " .. tostring(result)
	end
	return result
end

local SLOTS = { "child", "fallback", "item" }

--- Every node with ways to take it out or swap it, root first.
local function places(root)
	local list = {}
	local function visit(node, set, remove)
		list[#list + 1] = { node = node, set = set, remove = remove }
		for i = 1, #(node.children or {}) do
			visit(node.children[i], function(new)
				node.children[i] = new
			end, function()
				local old = table.remove(node.children, i)
				return function()
					table.insert(node.children, i, old)
				end
			end)
		end
		for _, slot in ipairs(SLOTS) do
			if node[slot] then
				visit(node[slot], function(new)
					node[slot] = new
				end, slot == "fallback" and function()
					local old = node.fallback
					node.fallback = nil
					return function()
						node.fallback = old
					end
				end or nil)
			end
		end
		for i = 1, #(node.pages or {}) do
			visit(node.pages[i], function(new)
				node.pages[i] = new
			end)
		end
	end
	visit(root)
	return list
end

local function inner(node)
	local list = {}
	for _, c in ipairs(node.children or {}) do
		list[#list + 1] = c
	end
	for _, slot in ipairs(SLOTS) do
		list[#list + 1] = node[slot]
	end
	for _, page in ipairs(node.pages or {}) do
		list[#list + 1] = page
	end
	return list
end

--- Smaller versions of the tree, each as a change and its undo.
local function edits(root)
	local list = {}
	for _, place in ipairs(places(root)) do
		local node = place.node
		if place.remove then
			list[#list + 1] = place.remove
		end
		if place.set then
			for _, sub in ipairs(inner(node)) do
				list[#list + 1] = function()
					place.set(sub)
					return function()
						place.set(node)
					end
				end
			end
			if node.kind ~= "text" then
				list[#list + 1] = function()
					place.set({ kind = "text", value = "x" })
					return function()
						place.set(node)
					end
				end
			end
		end
		if node.kind == "box" then
			for _, field in ipairs({ "props", "dynamic" }) do
				local names = vim.tbl_keys(node[field])
				table.sort(names)
				for _, name in ipairs(names) do
					list[#list + 1] = function()
						local old = node[field][name]
						node[field][name] = nil
						return function()
							node[field][name] = old
						end
					end
				end
			end
			if node.tag ~= "block" then
				list[#list + 1] = function()
					local old = node.tag
					node.tag = "block"
					return function()
						node.tag = old
					end
				end
			end
		end
	end
	return list
end

--- Shrinks a failing world to a small tree and few writes that still fail.
---@return table writes, string failure
function F.shrink(world, writes, width, budget)
	budget = budget or 1500
	local failure = F.replay(world, writes, width)
	if not failure then
		return writes, nil
	end

	local function try(change)
		if budget <= 0 then
			return false
		end
		budget = budget - 1
		local undo = change()
		local result = F.replay(world, writes, width)
		if result then
			failure = result
			return true
		end
		if undo then
			undo()
		end
		return false
	end

	local changed = true
	while changed and budget > 0 do
		changed = false
		for i = #writes, 1, -1 do
			local kept = writes
			if
				try(function()
					writes =
						vim.list_extend(vim.list_slice(kept, 1, i - 1), vim.list_slice(kept, i + 1))
					return function()
						writes = kept
					end
				end)
			then
				changed = true
			end
		end
		-- Edits go stale once one is kept, so the list is made again.
		local progress = true
		while progress and budget > 0 do
			progress = false
			for _, change in ipairs(edits(world.root)) do
				if try(change) then
					progress, changed = true, true
					break
				end
			end
		end
	end
	return writes, failure
end

--- The tree as indented lines, with the knobs each node reads.
function F.format(spec, indent, lines)
	indent, lines = indent or "", lines or {}
	local inspect = function(value)
		return vim.inspect(value, { newline = "", indent = "" })
	end
	local line = indent .. spec.kind
	if spec.tag then
		line = line .. " " .. spec.tag
		if next(spec.props) then
			line = line .. " " .. inspect(spec.props)
		end
		if next(spec.dynamic) then
			line = line .. " knobs " .. inspect(spec.dynamic)
		end
	end
	if spec.knob then
		line = line .. " knob " .. spec.knob
	end
	if spec.value then
		line = line .. " " .. inspect(spec.value)
	end
	if spec.text then
		line = line .. " else " .. inspect(spec.text)
	end
	lines[#lines + 1] = line
	for _, child in ipairs(spec.children or {}) do
		F.format(child, indent .. "  ", lines)
	end
	for _, slot in ipairs(SLOTS) do
		if spec[slot] then
			lines[#lines + 1] = indent .. "  ." .. slot
			F.format(spec[slot], indent .. "    ", lines)
		end
	end
	for i, page in ipairs(spec.pages or {}) do
		lines[#lines + 1] = indent .. "  .page " .. i
		F.format(page, indent .. "    ", lines)
	end
	return lines
end

--- A failure as a report: the smallest tree, its starting knobs and the writes.
function F.report(world, writes, failure)
	local used = {}
	local function walk(spec)
		if spec.knob then
			used[spec.knob] = true
		end
		for _, index in pairs(spec.dynamic or {}) do
			used[index] = true
		end
		for _, sub in ipairs(inner(spec)) do
			walk(sub)
		end
	end
	walk(world.root)
	local lines = { failure, "tree:" }
	vim.list_extend(lines, F.format(world.root, "  "))
	lines[#lines + 1] = "starting knobs:"
	local indexes = vim.tbl_keys(used)
	table.sort(indexes)
	for _, index in ipairs(indexes) do
		lines[#lines + 1] = "  " .. F.describe_write(world, index, world.initial[index])
	end
	lines[#lines + 1] = "writes:"
	for _, write in ipairs(writes) do
		lines[#lines + 1] = "  " .. F.describe_write(world, write[1], write[2])
	end
	return table.concat(lines, "\n")
end

return F
