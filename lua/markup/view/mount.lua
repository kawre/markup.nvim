--- Turns elements into engine commands.
---
--- Components run once, inside an owner. After that only the dynamic parts of
--- what they returned ever run again: a function child updates its own text
--- node, a function prop updates one style property, and `show` and `each`
--- mount and unmount their contents. Those parts each own a `contents` node, a
--- transparent group in the tree, so they never need to know their position.

local protocol = require("markup.view.protocol")
local reactive = require("markup.reactive")
local hl = require("markup.view.hl")
local defaults = require("markup.view.defaults")

local DISPLAY = protocol.display
local api = vim.api
local STYLE = protocol.style
local effect, scope, untrack = reactive.effect, reactive.scope, reactive.untrack

---@class markup.view.mount
local M = {}

--- Tags that map to a layout the engine has. Add a row here when the engine
--- gets a new `Display`.
local tags = {
	block = DISPLAY.block,
	inline = DISPLAY.inline,
	text = DISPLAY.inline,
	button = DISPLAY.block,
	root = DISPLAY.block,
	newl = DISPLAY.block,
	flex = DISPLAY.flex,
	hflex = DISPLAY.flex,
	vflex = DISPLAY.flex,
	grid = DISPLAY.grid,
}

local tag_props = {
	button = { width = "fit", interactive = true },
	newl = { height = 1 },
	vflex = { direction = "column" },
}

local unsupported = { inblock = true }

local shorthand = { margin = "margin", padding = "padding", inset = "inset" }

local expand_edges

--- Expands `margin = { 1, 2 }` style shorthands, CSS order.
expand_edges = function(result, name, value)
	if name == "inset" then
		local edges = {}
		expand_edges(edges, "edge", value)
		result.top, result.right = edges.edge_top, edges.edge_right
		result.bottom, result.left = edges.edge_bottom, edges.edge_left
		return
	end

	local top, right, bottom, left
	if type(value) == "number" then
		top, right, bottom, left = value, value, value, value
	else
		local n = #value
		top = value[1]
		right = n >= 2 and value[2] or top
		bottom = n >= 3 and value[3] or top
		left = n >= 4 and value[4] or right
	end
	result[name .. "_top"] = result[name .. "_top"] or top
	result[name .. "_right"] = result[name .. "_right"] or right
	result[name .. "_bottom"] = result[name .. "_bottom"] or bottom
	result[name .. "_left"] = result[name .. "_left"] or left
end

---@param view markup.view
local function apply_style(view, id, name, value)
	if name == "hl" then
		value = hl.id(value)
	end
	view.commands:set_style(id, name, value)
	view:request_commit()
end

--- Sends one style property, keeping it updated when it is a function.
local function bind_style(view, id, name, value)
	if type(value) == "function" then
		effect(function()
			apply_style(view, id, name, value())
		end)
	else
		apply_style(view, id, name, value)
	end
end

local function apply_props(view, id, tag, props)
	local fixed = tag_props[tag]
	if fixed then
		for name, value in pairs(fixed) do
			if props[name] == nil then
				bind_style(view, id, name, value)
			end
		end
	end

	local expanded
	for name, value in pairs(props) do
		if shorthand[name] then
			expanded = expanded or {}
			expand_edges(expanded, name, value)
		elseif name == "gap" then
			expanded = expanded or {}
			expanded.row_gap = type(value) == "table" and value[1] or value
			expanded.column_gap = type(value) == "table" and value[2] or value
		elseif name == "vertical" then
			bind_style(view, id, "direction", value and "column" or "row")
		elseif name == "columns" or name == "rows" then
			view.commands:set_tracks(id, name, value)
		elseif STYLE[name] then
			bind_style(view, id, name, value)
		end
	end

	if expanded then
		for name, value in pairs(expanded) do
			if props[name] == nil then
				bind_style(view, id, name, value)
			end
		end
	end

	local style = props.style
	if style == nil then
		style = defaults[tag]
	end
	if style ~= nil then
		bind_style(view, id, "hl", style)
	end

	if props.border then
		local border_style = props.border_style
		if border_style == nil and props.border == "half" and type(style) == "string" then
			border_style = hl.edge(style)
		end
		view.commands:set_border(id, props.border, props.border_sides, hl.id(border_style))
	end

	if props.on_hover then
		view:set_hover_handler(id, props.on_hover)
		reactive.on_cleanup(function()
			view:set_hover_handler(id, nil)
		end)
	end

	if props.on_press then
		view:set_handler(id, props.on_press)
		bind_style(view, id, "interactive", true)
		reactive.on_cleanup(function()
			view:set_handler(id, nil)
		end)
	end
end

local mount

local function mount_text(view, parent, before, value)
	local id = view:next_id()
	view.commands:create_text(id, tostring(value))
	view.commands:insert(parent, id, before)
	return id
end

--- A function child. Text updates in place, anything else is remounted.
local function mount_dynamic(view, parent, before, fn)
	local group = view:next_id()
	view.commands:create(group, DISPLAY.contents)
	view.commands:insert(parent, group, before)

	local text_id
	effect(function()
		local value = fn()
		local is_text = type(value) == "string" or type(value) == "number"

		if is_text and text_id then
			view.commands:set_text(text_id, tostring(value))
		else
			view.commands:clear(group)
			text_id = nil
			if is_text then
				text_id = mount_text(view, group, nil, value)
			else
				untrack(function()
					mount(view, value, group)
				end)
			end
		end
		view:request_commit()
	end)
end

local function mount_component(view, parent, before, element)
	local group = view:next_id()
	view.commands:create(group, DISPLAY.contents)
	view.commands:insert(parent, group, before)

	scope(function()
		mount(view, element.type(element.props or {}), group)
	end)
end

--- Moves an element into its own float, leaving a spacer in the flow.
local function mount_fixed(view, parent, before, element)
	local Fixed = require("markup.view.fixed")

	local props = vim.tbl_extend("force", {}, element.props)
	local overlay = props.overlay
	props.position, props.top, props.overlay = nil, nil, nil
	-- A band without a border is colored as a whole. With one, the element keeps
	-- its style and the float blends in with what is underneath.
	local style = props.style
	if props.border then
		style = false
	else
		props.style = nil
	end

	local spacer
	if not overlay then
		spacer = view:next_id()
		view.commands:create(spacer, DISPLAY.block)
		view.commands:insert(parent, spacer, before)
	end

	local fixed = Fixed(view, spacer, require("markup.element").new(element.type, props), style)
	table.insert(view.fixed, fixed)
	fixed:place()

	reactive.on_cleanup(function()
		fixed:dispose()
		view.fixed = vim.tbl_filter(function(other)
			return other ~= fixed
		end, view.fixed)
	end)
end

local function mount_host(view, parent, before, element)
	if element.props and element.props.position == "fixed" then
		return mount_fixed(view, parent, before, element)
	end

	local tag = element.type
	local display = tags[tag]

	if not display then
		if unsupported[tag] then
			error(("`%s` is not implemented by the engine yet"):format(tag), 0)
		end
		display = DISPLAY.block
	end

	local id = view:next_id()
	view.commands:create(id, display)

	local props = element.props or {}
	apply_props(view, id, tag, props)
	if props.children ~= nil then
		mount(view, props.children, id)
	end
	view.commands:insert(parent, id, before)
end

---@param view markup.view
---@param content any element, text, function, list or nothing
---@param parent integer
---@param before? integer
mount = function(view, content, parent, before)
	local kind = type(content)

	if content == nil or content == false then
		return
	elseif kind == "string" or kind == "number" then
		mount_text(view, parent, before, content)
	elseif kind == "function" then
		mount_dynamic(view, parent, before, content)
	elseif kind ~= "table" then
		error(("cannot render a %s"):format(kind), 0)
	elseif content.__type == "markup.element" then
		local element_type = content.type
		if type(element_type) == "function" then
			mount_component(view, parent, before, content)
		elseif type(element_type) == "table" and element_type.mount then
			element_type.mount(view, parent, before, content.props or {})
		elseif element_type == "fragment" then
			mount(view, (content.props or {}).children, parent, before)
		else
			mount_host(view, parent, before, content)
		end
	else
		for i = 1, table.maxn(content) do
			mount(view, content[i], parent, before)
		end
	end
end

M.mount = mount

local function element(control, props)
	return require("markup.element").new(control, props)
end

local Show = { typeof = "control" }

function Show.mount(view, parent, before, props)
	local group = view:next_id()
	view.commands:create(group, DISPLAY.contents)
	view.commands:insert(parent, group, before)

	local outer = reactive.current_owner()
	local shown, inner
	effect(function()
		local visible = not not props.when()
		if visible == shown then
			return
		end
		shown = visible

		if inner then
			reactive.dispose(inner)
			inner = nil
		end
		view.commands:clear(group)

		local content = visible and props.children or props.fallback
		if content then
			untrack(function()
				local _, created = scope(function()
					local value = content
					if type(value) == "function" then
						value = value()
					end
					mount(view, value, group)
				end, outer)
				inner = created
			end)
		end
		view:request_commit()
	end)
end

local Collapse = { typeof = "control" }

local COLLAPSE_DURATION = 180

function Collapse.mount(view, parent, before, props)
	local animate = Markup.animate
	local outer_owner = reactive.current_owner()

	-- The outer block is what animates, the inner one measures the content.
	local outer = view:next_id()
	view.commands:create(outer, DISPLAY.block)
	view.commands:set_style(outer, "overflow", "hidden")
	view.commands:insert(parent, outer, before)

	local inner, inner_owner
	local height = animate.value(0, { duration = props.duration or COLLAPSE_DURATION })
	local settled = false

	local function mount_content()
		if inner then
			return
		end
		inner = view:next_id()
		view.commands:create(inner, DISPLAY.block)
		view.commands:insert(outer, inner)

		local content = props.children
		untrack(function()
			local _, owner = scope(function()
				local value = content
				if type(value) == "function" then
					value = value()
				end
				mount(view, value, inner)
			end, outer_owner)
			inner_owner = owner
		end)
	end

	local function unmount_content()
		if inner then
			reactive.dispose(inner_owner)
			view.commands:remove(inner)
			inner, inner_owner = nil, nil
			view:request_commit()
		end
	end

	local function set_height(value)
		view.commands:set_style(outer, "height", value)
		view:request_commit()
	end

	effect(function()
		-- Read first: a settled block must still hear the next change.
		local value = height()
		if not settled then
			set_height(math.floor(value + 0.5))
		end
	end)

	local function natural_height()
		local ok, node = pcall(view.engine.describe, view.engine, inner)
		return ok and node.outer_height or 0
	end

	local shown
	effect(function()
		local visible = not not props.when()
		if visible == shown then
			return
		end

		local first = shown == nil
		shown = visible

		if visible then
			mount_content()
			if first then
				settled = true
				set_height("auto")
				return
			end

			view:after_commit(function()
				if not shown then
					return
				end
				settled = false
				height(natural_height(), {
					done = function()
						settled = true
						set_height("auto")
					end,
				})
			end)
		elseif not first then
			if settled then
				settled = false
				height(natural_height(), { duration = 0 })
			end
			height(0, { done = unmount_content })
		else
			set_height(0)
		end

		view:request_commit()
	end)
end

--- Like `show`, but the height animates and hidden content unmounts afterwards.
---@param when fun(): any
---@param content any element, or a function called on each mount
---@param opts? { duration?: number }
function M.collapse(when, content, opts)
	return element(Collapse, { when = when, children = content, duration = opts and opts.duration })
end

local Slide = { typeof = "control" }

local SLIDE_DURATION = 320

function Slide.mount(view, parent, before, props)
	local animate = Markup.animate
	local outer_owner = reactive.current_owner()

	-- The track holds the pages side by side, and moves behind the outer block.
	local outer = view:next_id()
	view.commands:create(outer, DISPLAY.block)
	view.commands:set_style(outer, "overflow_x", "hidden")
	view.commands:insert(parent, outer, before)

	local track = view:next_id()
	view.commands:create(track, DISPLAY.flex)
	view.commands:set_style(track, "position", "relative")
	view.commands:set_style(track, "left", 0)
	view.commands:insert(outer, track)

	local offset = animate.value(0, {
		duration = props.duration or SLIDE_DURATION,
		easing = "in_out_cubic",
	})

	effect(function()
		view.commands:set_style(track, "left", -math.floor(offset() + 0.5))
		view:request_commit()
	end)

	local pages = {} ---@type table<integer, { owner: table }>

	effect(function()
		local width = view:columns()
		for id in pairs(pages) do
			view.commands:set_style(id, "width", width)
		end
		view:request_commit()
	end)

	local function mount_page(key, next_page)
		local id = view:next_id()
		view.commands:create(id, DISPLAY.block)
		view.commands:set_style(id, "width", view.width_cells())
		view.commands:set_style(id, "shrink", 0)
		view.commands:insert(track, id, next_page)

		untrack(function()
			local _, owner = scope(function()
				mount(view, props.render(key), id)
			end, outer_owner)
			pages[id] = { owner = owner }
		end)
		return id
	end

	local function unmount_page(id)
		reactive.dispose(pages[id].owner)
		pages[id] = nil
		view.commands:remove(id)
		view:request_commit()
	end

	local cursors = {} ---@type table<any, integer[]>
	local current_key, current_page, leaving

	--- Drops the page that moved away, leaving the other one at the start.
	local function settle()
		if leaving then
			unmount_page(leaving)
			leaving = nil
			offset(0, { duration = 0 })
		end
	end

	--- Back to where the cursor was on this page, or to the top of a new one.
	local function restore_cursor(key)
		view:after_commit(function()
			if view.win:win_valid() then
				local cursor = cursors[key] or { 1, 0 }
				local last = api.nvim_buf_line_count(view.win.buf)
				api.nvim_win_set_cursor(view.win.win, { math.min(cursor[1], last), cursor[2] })
				view.cursor = nil
				view:snap_cursor()
			end
		end)
	end

	effect(function()
		local key = props.key()
		if key == current_key then
			return
		end

		if current_key == nil then
			current_key, current_page = key, mount_page(key)
			return
		end

		settle()

		if view.win:win_valid() then
			cursors[current_key] = api.nvim_win_get_cursor(view.win.win)
		end

		local forward = not props.forward or props.forward(current_key, key)
		local width = untrack(function()
			return view:columns()
		end)

		leaving = current_page
		current_key = key

		local function arrive()
			settle()
			restore_cursor(key)
		end

		if forward then
			current_page = mount_page(key)
			offset(width, { done = arrive })
		else
			current_page = mount_page(key, leaving)
			offset(width, { duration = 0 })
			offset(0, { done = arrive })
		end
	end)
end

--- Shows the page for `key()`, sliding sideways whenever it changes. The page
--- moving away unmounts once it is gone, and the cursor returns to where it was
--- when coming back to a page.
---@generic K
---@param key fun(): K
---@param render fun(key: K): any
---@param opts? { duration?: number, forward?: fun(from: K, to: K): boolean } `forward`
--- says if the new page comes in from the right, which it does by default
function M.slide(key, render, opts)
	opts = opts or {}
	return element(Slide, { key = key, render = render, forward = opts.forward, duration = opts.duration })
end

--- Renders `content` while `when()` is truthy, and `fallback` otherwise.
---@param when fun(): any
---@param content any element, or a function called on each mount
---@param fallback? any
function M.show(when, content, fallback)
	return element(Show, { when = when, children = content, fallback = fallback })
end

local Each = { typeof = "control" }

function Each.mount(view, parent, before, props)
	local list, render = props.list, props.render
	local key_of = props.key or function(item)
		return item
	end

	local group = view:next_id()
	view.commands:create(group, DISPLAY.contents)
	view.commands:insert(parent, group, before)

	local outer = reactive.current_owner()
	local entries = {} ---@type table<any, { id: integer, owner: table }>
	local order = {} ---@type any[]

	local function create(item, index, next_id)
		local id = view:next_id()
		view.commands:create(id, DISPLAY.contents)
		view.commands:insert(group, id, next_id)
		local _, owner = scope(function()
			mount(view, render(item, index), id)
		end, outer)
		return { id = id, owner = owner }
	end

	effect(function()
		local items = list()
		local keys, wanted = {}, {}
		for i, item in ipairs(items) do
			local key = key_of(item)
			assert(not wanted[key], ("`each` got the key %s twice"):format(tostring(key)))
			keys[i], wanted[key] = key, true
		end

		-- Whatever left the list goes first, so what remains can be compared.
		local remaining = {}
		for _, key in ipairs(order) do
			if wanted[key] then
				remaining[#remaining + 1] = key
			else
				reactive.dispose(entries[key].owner)
				view.commands:remove(entries[key].id)
				entries[key] = nil
			end
		end

		-- Walk both orders. Items already in sequence need no command at all.
		local placed = {}
		local cursor = 1
		local function current()
			while remaining[cursor] ~= nil and placed[remaining[cursor]] do
				cursor = cursor + 1
			end
			return remaining[cursor]
		end

		untrack(function()
			for i, key in ipairs(keys) do
				local expected = current()
				if key == expected then
					cursor = cursor + 1
				else
					local next_id = expected ~= nil and entries[expected].id or nil
					if entries[key] then
						view.commands:insert(group, entries[key].id, next_id)
					else
						entries[key] = create(items[i], i, next_id)
					end
				end
				placed[key] = true
			end
		end)

		order = keys
		view:request_commit()
	end)
end

--- Renders `render(item, index)` for each item of `list()`, keeping the UI of
--- items that stay. Items are their own key unless `opts.key` says otherwise.
---@generic T
---@param list fun(): T[]
---@param render fun(item: T, index: integer): any
---@param opts? { key?: fun(item: T): any }
function M.each(list, render, opts)
	return element(Each, { list = list, render = render, key = opts and opts.key })
end

return M
