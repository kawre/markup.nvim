local Element = require("markup.element")

---@alias markup.factory.element.style string|vim.api.keyset.highlight

---@class markup.factory.element.children.dynamic
---@field [number] markup.factory.element.children

---@alias markup.factory.element.children number|string|table|markup.factory.element.children.dynamic

---@alias markup.length integer|"auto"|"fit"|"full" cells, or as wide as there is room, the content, or the parent
---@alias markup.edges integer|integer[] one value for every side, or CSS order: `{ y, x }`, `{ top, x, bottom }`, `{ top, right, bottom, left }`
---@alias markup.align "start"|"end"|"center"|"stretch"
---@alias markup.justify "start"|"end"|"center"|"between"|"around"|"evenly"|"stretch"
---@alias markup.track integer|"auto"|string cells, as wide as the content, or a share such as `"1fr"`
---@alias markup.border "single"|"rounded"|"double"|"heavy"|"half"|{ chars: string }
---@alias markup.overflow "visible"|"hidden"|"clip" `visible` shows what does not fit, `hidden` cuts it off and makes the box a scroll container, `clip` cuts it off along one axis alone

--- Props every element takes. When a prop accepts a value or a function, the
--- function is read again whenever a signal it reads changes.
---@class markup.node.props
---@field children? markup.factory.element.children
---@field style? markup.factory.element.style|fun(): markup.factory.element.style? highlight group, or attributes of one
--- Box
---@field display? "block"|"inline"|"flex"|"grid" overrides the tag's layout mode when the element mounts
---@field width? markup.length|fun(): markup.length
---@field height? markup.length|fun(): markup.length as in CSS, the box keeps it, and what is taller shows below it; `min_height` grows with the content
---@field min_width? markup.length|fun(): markup.length
---@field max_width? markup.length|fun(): markup.length
---@field min_height? markup.length|fun(): markup.length
---@field max_height? markup.length|fun(): markup.length
---@field margin? markup.edges|fun(): markup.edges vertical margins between blocks collapse, as in CSS: siblings share the larger, and a first or last child's passes through a parent with no padding or border there
---@field margin_top? integer|fun(): integer
---@field margin_right? integer|fun(): integer
---@field margin_bottom? integer|fun(): integer
---@field margin_left? integer|fun(): integer
---@field padding? markup.edges|fun(): markup.edges
---@field padding_top? integer|fun(): integer
---@field padding_right? integer|fun(): integer
---@field padding_bottom? integer|fun(): integer
---@field padding_left? integer|fun(): integer
---@field border? markup.border drawn inside the box, around the padding
---@field border_style? string highlight of the border
---@field border_sides? ("top"|"right"|"bottom"|"left")[] the sides to draw, all by default
---@field overflow? markup.overflow|fun(): markup.overflow sets `overflow_x` and `overflow_y`, as in CSS
---@field overflow_x? markup.overflow|fun(): markup.overflow cuts off what is too wide. As in CSS, `hidden` on either axis cuts off both, whatever the other one says, and makes the box a scroll container: as a flex or grid item, it may shrink below its content. `clip` cuts off only this axis, unless `overflow_y` is `hidden`
---@field overflow_y? markup.overflow|fun(): markup.overflow cuts off what is too tall. As in CSS, `hidden` on either axis cuts off both, whatever the other one says, and makes the box a scroll container: as a flex or grid item, it may shrink below its content. `clip` cuts off only this axis, unless `overflow_x` is `hidden`
---@field text_overflow? "clip"|"ellipsis"|string|fun(): "clip"|"ellipsis"|string as CSS `text-overflow`, what single-line text ends in where its width is cut off, by `overflow_x` or by `hidden` on either axis: "clip" (default) or "" cuts it, "ellipsis" ends it in …, and any other string ends it in that string. Needs `white_space = "nowrap"`, or text wraps and nothing is cut. The marker takes the style of this element
---@field white_space? "normal"|"nowrap"|fun(): "normal"|"nowrap" whether text wraps, inherited
--- Flex and grid
---@field direction? "row"|"column"|fun(): "row"|"column"
---@field vertical? boolean|fun(): boolean shorthand for `direction = "column"`
---@field reverse? boolean|fun(): boolean
---@field wrap? boolean|fun(): boolean
---@field justify? markup.justify|fun(): markup.justify
---@field align? markup.align|fun(): markup.align
---@field align_content? markup.justify|fun(): markup.justify
---@field align_self? markup.align|"auto"|fun(): markup.align|"auto"
---@field justify_items? markup.align|fun(): markup.align
---@field justify_self? markup.align|"auto"|fun(): markup.align|"auto"
---@field gap? integer|integer[]|fun(): integer|integer[] between children, or `{ rows, columns }`
---@field row_gap? integer|fun(): integer
---@field column_gap? integer|fun(): integer
---@field spacing? integer|fun(): integer the least gap between children
---@field grow? number|fun(): number
---@field shrink? number|fun(): number
---@field basis? markup.length|fun(): markup.length
---@field order? integer|fun(): integer
---@field columns? integer|markup.track[] grid columns, or how many equal ones
---@field rows? integer|markup.track[] grid rows, or how many equal ones
---@field auto_flow? "row"|"column"|fun(): "row"|"column"
---@field column? integer|fun(): integer grid column to start in
---@field row? integer|fun(): integer grid row to start in
---@field column_span? integer|fun(): integer
---@field row_span? integer|fun(): integer
--- Position
---@field position? "static"|"relative"|"absolute"|"fixed" `fixed` pins the element above the view, in a float of its own
---@field overlay? boolean with `fixed`, float over the content rather than pushing it down
---@field inset? markup.edges|fun(): markup.edges shorthand for `top`, `right`, `bottom` and `left`
---@field top? integer|fun(): integer
---@field right? integer|fun(): integer
---@field bottom? integer|fun(): integer
---@field left? integer|fun(): integer
---@field z? integer|fun(): integer
--- Interaction
---@field on_press? fun() called on <CR>, or on a click, which makes the element a place the cursor can land
---@field click? "single"|"double"|false which click of the mouse presses it, single by default
---@field on_hover? fun(hovered: boolean) called as the cursor comes onto the element and leaves it
---@field interactive? boolean|fun(): boolean a place the cursor can land, without `on_press`
---@field inert? boolean|fun(): boolean the element and all in it take no cursor: no snapping onto them, no hover, no press
---@field snap? boolean|fun(): boolean with `false`, a view with `snap = "text"` moves the cursor
--- past the text in here, such as labels and decoration. Inherited, so `true` inside brings it
--- back. Interactive nodes are always a place to land.

---@alias markup.factory.element.fragment.props
---| { children?: markup.factory.element.children }
---| markup.factory.element.children

---@alias markup.factory.element.props
---| { children?: markup.factory.element.children }
---| markup.factory.element.children
---| markup.node.props

---@alias markup.factory.element.new
---| fun(props?: markup.factory.element.props, style?: markup.factory.element.style): markup.element

---@class markup.factory.element
---@overload fun(type: any, props?: markup.factory.element.props, style?: markup.factory.element.style): markup.element
local M = Markup.singleton()

local function resolve(props, style)
	if type(props) ~= "table" or getmetatable(props) then
		-- single child or no props
		props = { children = props }
	else
		if not props.children then
			local new_props = {}
			local positions = {}

			for key, value in pairs(props) do
				if type(key) == "number" then
					positions[#positions + 1] = key
				else
					new_props[key] = value
				end
			end

			-- In the order they were written. `pairs` promises no order, and a
			-- child it put first would be laid out first.
			if #positions > 0 then
				table.sort(positions)
				local children = {}
				for i, position in ipairs(positions) do
					children[i] = props[position]
				end
				new_props.children = children
			end

			props = new_props
		end

		if type(props.children) == "table" and #props.children == 1 then
			-- if children is a table with a single element, unwrap it
			props.children = props.children[1]
		end
	end

	if style then
		-- second style takes priority over props.style
		props.style = style
	end

	return props
end

---@param type any
---@param props? markup.factory.element.props
---@param style? markup.factory.element.style
function M.call(type, props, style)
	return Element.new(type, resolve(props, style))
end

---@type markup.factory.element.new
function M.inline(props, style)
	return M.call("inline", props, style)
end

---@type markup.factory.element.new
function M.text(props, style)
	return M.call("inline", props, style)
end

---@type markup.factory.element.new
function M.block(props, style)
	return M.call("block", props, style)
end

---@type markup.factory.element.new
function M.inblock(props, style)
	return M.call("inblock", props, style)
end

function M.newl()
	return M.call("newl", {})
end

---@type markup.factory.element.new
function M.flex(props, style)
	return M.call("flex", props, style)
end

---@generic T
---@param fn fun(props?: T): any
---@return fun(props?: T): any
function M.component(fn)
	return function(props)
		return M.call(fn, props)
	end
end

---@param Class table
function M.class(Class)
	return function(...)
		Class.typeof = "class"
		return M.call(Class, ...)
	end
end

---@param props? markup.factory.element.fragment.props
function M.fragment(props)
	return M.call("fragment", props)
end

return M
