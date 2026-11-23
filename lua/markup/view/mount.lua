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

--- Expands `margin = { 1, 2 }` style shorthands, CSS order.
local function expand_edges(result, name, value)
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

--- Shorthands, each to the properties it stands for.
local shorthands = {
	margin = function(value)
		local sides = {}
		expand_edges(sides, "margin", value)
		return sides
	end,
	padding = function(value)
		local sides = {}
		expand_edges(sides, "padding", value)
		return sides
	end,
	inset = function(value)
		local sides = {}
		expand_edges(sides, "inset", value)
		return sides
	end,
	-- Both axes, as in CSS. `overflow_x` or `overflow_y` given on its own wins.
	overflow = function(value)
		return { overflow_x = value, overflow_y = value }
	end,
	gap = function(value)
		local rows, columns = value, value
		if type(value) == "table" then
			rows, columns = value[1], value[2]
		end
		return { row_gap = rows, column_gap = columns }
	end,
}

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
		local expand = shorthands[name]
		if expand and type(value) == "function" then
			-- Each side the element gives on its own wins, as it does below.
			effect(function()
				for side, side_value in pairs(expand(value())) do
					if props[side] == nil then
						apply_style(view, id, side, side_value)
					end
				end
			end)
		elseif expand then
			expanded = expanded or {}
			for side, side_value in pairs(expand(value)) do
				expanded[side] = side_value
			end
		elseif name == "vertical" then
			-- A shorthand, so `direction` wins, as `padding_left` does over `padding`.
			if props.direction == nil then
				local function direction(vertical)
					return vertical and "column" or "row"
				end
				bind_style(view, id, "direction", type(value) == "function" and function()
					return direction(value())
				end or direction(value))
			end
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
	if tag == "canvas" and style ~= nil then
		effect(function()
			local current = style
			if type(style) == "function" then
				current = style()
			end
			local unsubscribe = hl.canvas_background(hl.id(current), function(background)
				view.commands:set_style(id, "hl", background)
				view:request_commit()
			end)
			reactive.on_cleanup(unsubscribe)
		end)
	elseif style ~= nil then
		bind_style(view, id, "hl", style)
	end

	if props.border then
		--- A half border draws in the background of the element, whichever
		--- group that is at the moment.
		local function set_border(current)
			local border_style = props.border_style
			if border_style == nil and props.border == "half" and type(current) == "string" then
				border_style = hl.edge(current)
			end
			local border_hl = hl.id(border_style)
			if tag == "canvas" then
				border_hl = hl.canvas(border_hl)
			end
			view.commands:set_border(id, props.border, props.border_sides, border_hl)
			view:request_commit()
		end

		if props.border_style == nil and props.border == "half" and type(style) == "function" then
			effect(function()
				set_border(style())
			end)
		else
			set_border(style)
		end
	end

	if props.on_hover then
		view:set_hover_handler(id, props.on_hover)
		reactive.on_cleanup(function()
			view:set_hover_handler(id, nil)
		end)
	end

	if props.on_press then
		view:set_handler(id, props.on_press, props.click)
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
		style = nil
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
	local props = element.props or {}
	if props.position == "fixed" then
		return mount_fixed(view, parent, before, element)
	end

	local tag = element.type
	if unsupported[tag] then
		error(("`%s` is not implemented by the engine yet"):format(tag), 0)
	end

	local display = tags[tag] or DISPLAY.block
	if props.display ~= nil then
		display = DISPLAY[props.display]
		if not display or display == DISPLAY.contents then
			error(("invalid display `%s`"):format(tostring(props.display)), 0)
		end
	end

	local id = view:next_id()
	view.commands:create(id, display)
	-- In place before anything that can fail, so a mount that fails halfway
	-- leaves what it made where the next clear of the parent frees it.
	view.commands:insert(parent, id, before)

	apply_props(view, id, tag, props)
	if props.children ~= nil then
		mount(view, props.children, id)
	end
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
	-- Only the rows, as CSS `clip`: what is wider than the collapse stays readable.
	view.commands:set_style(outer, "overflow_y", "clip")
	view.commands:insert(parent, outer, before)

	local inner, inner_owner
	local height = animate.value(0, { duration = props.duration or COLLAPSE_DURATION, step = 1 })
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
				local natural = natural_height()
				height(natural, { duration = 0 })
				-- The signal may hold this already, and then nothing writes it
				-- over "auto": empty content would stay as tall as its row.
				set_height(natural)
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

local Image = { typeof = "control" }

function Image.mount(view, parent, before, props)
	local images = require("markup.image")

	local id = view:next_id()
	view.commands:create(id, DISPLAY.block)
	view.commands:insert(parent, id, before)

	-- Without anything to show images, the box keeps its place and says what
	-- would be there.
	if not images.available() and props.alt then
		mount(view, require("markup").inline(props.alt, "Comment"), id)
	end

	effect(function()
		local data = props.data
		if type(data) == "function" then
			data = data()
		end

		local function value(prop)
			if type(prop) == "function" then
				return prop()
			end
			return prop
		end

		-- A list of frames plays like a GIF, at each frame's own delay.
		local frames = type(data) == "table" and #data > 0 and data or nil
		local first = frames and frames[1].data or (type(data) == "string" and data or nil)

		local width, height = images.size(first, value(props.width), value(props.height))
		view.commands:set_style(id, "width", width)
		view.commands:set_style(id, "height", height)

		if not frames or #frames == 1 then
			view:set_image(id, first and { data = first, width = width, height = height } or nil)
			view:request_commit()
			return
		end

		-- When each frame starts, in ms from the start of the loop.
		local starts, total = {}, 0
		for i, frame in ipairs(frames) do
			starts[i] = total
			total = total + math.max(frame.delay or 100, 20)
		end
		local function frame_at(ms)
			local index = 1
			for i = #starts, 1, -1 do
				if ms >= starts[i] then
					index = i
					break
				end
			end
			return index
		end

		local index = reactive.signal(1)
		Markup.animate.run({
			duration = total,
			easing = "linear",
			loop = true,
			-- Sleeps until the next frame is due.
			next = function(running)
				local at = running % total
				local following = starts[frame_at(at) + 1] or total
				return following - at
			end,
			update = function(progress)
				index(frame_at(progress * total))
			end,
		})
		effect(function()
			view:set_image(id, { data = frames[index()].data, width = width, height = height })
			view:request_commit()
		end)
	end)

	reactive.on_cleanup(function()
		view:set_image(id, nil)
	end)
end

--- An image, as a box in the layout that it is drawn over.
---@param props { data: string|markup.image.frame[]|fun(): (string|markup.image.frame[])?, width?: integer|fun(): integer, height?: integer|fun(): integer, alt?: string }
--- `data` is the bytes of a PNG, or a list of frames that play in a loop like a
--- GIF, or a function giving either once they are there. A missing height
--- follows the proportions of the image.
function M.image(props)
	return element(Image, props)
end

local Canvas = { typeof = "control" }

--- An explicit cell count (`0` or `>= 1`), or nil for layout-derived sizes
--- (`"auto"`, `"full"`, `"fit"`, or fractional shares `0 < v < 1`).
---@param value any
---@return integer?
local function cell_size(value)
	if type(value) == "number" and (value == 0 or value >= 1) then
		return math.floor(value)
	end
end

--- Errors when nothing sizes a canvas side. A CSS canvas without a size
--- takes its bitmap's; this one has none, so `auto` and `fit` need a min,
--- grow or basis to go on.
---@param axis "width"|"height"
---@param value any
---@param props markup.canvas.props
local function check_side(axis, value, props)
	local unsized = value == nil or value == "auto" or value == "fit"
	if unsized and props["min_" .. axis] == nil and props.grow == nil and props.basis == nil then
		error(
			("canvas %s `%s` has nothing to size it: give cells, `full`, a share or `min_%s`"):format(
				axis,
				tostring(value or "auto"),
				axis
			),
			0
		)
	end
end

function Canvas.mount(view, parent, before, props)
	if props.position == "fixed" then
		return mount_fixed(view, parent, before, element(Canvas, props))
	end

	local canvas = require("markup.view.canvas")
	-- As in CSS: inline unless told otherwise, and a positioned box is a block.
	-- A flex or grid item is a box either way.
	local display = props.display or "inline"
	if display ~= "inline" and display ~= "block" then
		error(("canvas display `%s` must be `inline` or `block`"):format(tostring(display)), 0)
	end
	if props.position == "absolute" then
		display = "block"
	end
	local id = view:next_id()
	view.commands:create(id, DISPLAY[display], true)
	view.commands:insert(parent, id, before)

	apply_props(view, id, "canvas", props)

	local draw = props.draw
	if not draw then
		return
	end

	for _, axis in ipairs({ "width", "height" }) do
		if type(props[axis]) ~= "function" then
			check_side(axis, props[axis], props)
		end
	end

	local constrained = props.min_width ~= nil
		or props.max_width ~= nil
		or props.min_height ~= nil
		or props.max_height ~= nil
		or props.grow ~= nil
		or props.shrink ~= nil
		or props.basis ~= nil
	local fixed_w = cell_size(props.width) ~= nil
	local fixed_h = cell_size(props.height) ~= nil
	local track_layout = constrained or not (fixed_w and fixed_h)

	local laid_width = reactive.signal(nil)
	local laid_height = reactive.signal(nil)

	if track_layout then
		local prev_w, prev_h
		local unsubscribe = view:on_commit(function()
			local ok, node = pcall(view.engine.describe, view.engine, id)
			if not ok then
				return
			end
			if node.content_width ~= prev_w or node.content_height ~= prev_h then
				prev_w, prev_h = node.content_width, node.content_height
				laid_width(prev_w)
				laid_height(prev_h)
				if reactive.forced() then
					reactive.flush()
				end
			end
		end)
		reactive.on_cleanup(unsubscribe)
	end

	local ctx = canvas.context(0, 0)
	effect(function()
		local raw_w = type(props.width) == "function" and props.width() or props.width
		local raw_h = type(props.height) == "function" and props.height() or props.height
		if type(props.width) == "function" then
			check_side("width", raw_w, props)
		end
		if type(props.height) == "function" then
			check_side("height", raw_h, props)
		end
		local w = cell_size(raw_w)
		local h = cell_size(raw_h)

		if constrained then
			w = laid_width() or w
			h = laid_height() or h
		else
			if not w then
				w = laid_width()
			end
			if not h then
				h = laid_height()
			end
		end

		if not w or not h then
			return
		end

		if ctx.width ~= w or ctx.height ~= h then
			ctx:resize(w, h)
		elseif not props.retain then
			ctx:clear()
		end

		if w > 0 and h > 0 then
			ctx:begin()
			draw(ctx)
		end
		ctx:flush(view.commands, id)
		view:request_commit()
	end)
end

---@class markup.canvas.props: markup.node.props
---@field display? "inline"|"block" `inline` (the default) sits in a line, as an inline-block; `block` takes lines of its own
---@field draw? fun(ctx: markup.canvas.context) called inside a reactive effect to paint the surface; redrawing runs no layout
---@field retain? boolean keep previous cells between redraws instead of clearing first

--- A 2D cell surface drawn directly by `draw(ctx)`, which never lays anything
--- out. As a CSS `<canvas>`, it is inline unless `display = "block"`, and its
--- size is what `width` and `height` say: cells, `"full"`, a share, or `auto`
--- with a min, `grow` or `basis`. What it leaves blank shows what is under it,
--- and what it draws takes nothing from the boxes around it: a cell's style
--- is all it has, with `Normal`'s foreground when that sets none, over the
--- background under it. A background in its own `style` hides what
--- is under it. Takes all standard box props (`border`, `padding`, `margin`,
--- `on_press`, ...).
---@param props markup.canvas.props
function M.canvas(props)
	return element(Canvas, props)
end

local Slide = { typeof = "control" }

local SLIDE_DURATION = 320

function Slide.mount(view, parent, before, props)
	local animate = Markup.animate
	local outer_owner = reactive.current_owner()

	-- The track holds the pages side by side, and moves behind the outer block.
	local outer = view:next_id()
	view.commands:create(outer, DISPLAY.block)
	-- Only the columns, as CSS `clip`: a page taller than the slide still shows.
	view.commands:set_style(outer, "overflow_x", "clip")
	view.commands:insert(parent, outer, before)

	local track = view:next_id()
	view.commands:create(track, DISPLAY.flex)
	view.commands:set_style(track, "position", "relative")
	view.commands:set_style(track, "left", 0)
	view.commands:insert(outer, track)

	local offset = animate.value(0, {
		duration = props.duration or SLIDE_DURATION,
		easing = "in_out_cubic",
		step = 1,
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

	--- Whether the slide is the whole view, as pages of an app are, and so the
	--- cursor is its to move: back to where it was on a page, or to the top of a
	--- new one. A slide that is part of a page, such as a carousel, leaves the
	--- cursor alone, wherever it is.
	local function holds_cursor()
		if not view.win:win_valid() or api.nvim_win_get_buf(view.win.win) ~= view.win.buf then
			return false
		end
		local ok, node = pcall(view.engine.describe, view.engine, outer)
		if not ok or not node.x then
			return false
		end
		return node.y == 0 and node.y + node.outer_height >= api.nvim_buf_line_count(view.win.buf)
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

	local function change(key)
		if key == current_key then
			return
		end

		if current_key == nil then
			current_key, current_page = key, mount_page(key)
			return
		end

		settle()

		local had_cursor = holds_cursor()
		if had_cursor then
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
			if had_cursor then
				restore_cursor(key)
			end
		end

		if forward then
			current_page = mount_page(key)
			offset(width, { done = arrive })
		else
			current_page = mount_page(key, leaving)
			offset(width, { duration = 0 })
			offset(0, { done = arrive })
		end
	end

	-- Only the key may rerun this: a rerun stops the slide under way, so anything
	-- else it reads, such as the width, must not be tracked.
	effect(function()
		local key = props.key()
		untrack(function()
			change(key)
		end)
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
	return element(
		Slide,
		{ key = key, render = render, forward = opts.forward, duration = opts.duration }
	)
end

--- Renders `content` while `when()` is truthy, and `fallback` otherwise.
---@param when fun(): any
---@param content any element, or a function called on each mount
---@param fallback? any
function M.show(when, content, fallback)
	return element(Show, { when = when, children = content, fallback = fallback })
end

local Each = { typeof = "control" }

--- Which of `keys` stay where they are: the longest run whose `position`
--- before only goes up. Keys with no position are new.
---@param keys any[]
---@param position table<any, integer>
---@return table<integer, true> indexes into `keys`
local function stable(keys, position)
	-- For each length, the index of the run of that length ending lowest.
	local tails, previous = {}, {}
	for i, key in ipairs(keys) do
		local at = position[key]
		if at then
			local low, high = 1, #tails + 1
			while low < high do
				local middle = math.floor((low + high) / 2)
				if position[keys[tails[middle]]] < at then
					low = middle + 1
				else
					high = middle
				end
			end
			tails[low] = i
			previous[i] = tails[low - 1]
		end
	end
	local stays, i = {}, tails[#tails]
	while i do
		stays[i] = true
		i = previous[i]
	end
	return stays
end

function Each.mount(view, parent, before, props)
	local list, render = props.list, props.render
	local key_of = props.key or function(item)
		return item
	end

	local group = view:next_id()
	view.commands:create(group, DISPLAY.contents)
	view.commands:insert(parent, group, before)

	local outer = reactive.current_owner()
	local entries = {} ---@type table<any, { id: integer, owner: table, item: function, index: function }>
	local order = {} ---@type any[]

	local function create(item, index, next_id)
		local id = view:next_id()
		view.commands:create(id, DISPLAY.contents)
		view.commands:insert(group, id, next_id)
		local current_item, current_index = reactive.signal(item), reactive.signal(index)
		local _, owner = scope(function()
			mount(view, render(current_item, current_index), id)
		end, outer)
		return { id = id, owner = owner, item = current_item, index = current_index }
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

		-- The longest run of items already in order stays where it is, and only
		-- the rest moves: swapping two rows moves two, not every row between.
		local position = {}
		for i, key in ipairs(remaining) do
			position[key] = i
		end
		local stays = stable(keys, position)

		untrack(function()
			-- Each item that moves or is new goes in before the next that stays,
			-- in list order, so what moves before the same one keeps its order.
			local anchors, anchor = {}, nil
			for i = #keys, 1, -1 do
				anchors[i] = anchor
				if stays[i] then
					anchor = entries[keys[i]].id
				end
			end

			for i, key in ipairs(keys) do
				local entry = entries[key]
				if entry then
					local item = items[i]
					-- A function-valued item is data. A signal normally treats it as an updater.
					if type(item) == "function" then
						entry.item(function()
							return item
						end)
					else
						entry.item(item)
					end
					entry.index(i)
					if not stays[i] then
						view.commands:insert(group, entry.id, anchors[i])
					end
				else
					entries[key] = create(items[i], i, anchors[i])
				end
			end
		end)

		order = keys
		view:request_commit()
	end)
end

--- Mounts each key once. The render callback receives accessors for its current
--- item and one-based index. Items are their own key unless `opts.key` says otherwise.
---@generic T
---@param list fun(): T[]
---@param render fun(item: (fun(): T), index: (fun(): integer)): any
---@param opts? { key?: fun(item: T): any }
function M.each(list, render, opts)
	return element(Each, { list = list, render = render, key = opts and opts.key })
end

return M
