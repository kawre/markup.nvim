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

--- Props every element takes. Each value can also be a function, which is read
--- again whenever a signal it reads changes, updating only that property.
---@class markup.node.props
---@field children? markup.factory.element.children
---@field style? markup.factory.element.style|fun(): markup.factory.element.style? highlight group, or attributes of one
--- Box
---@field width? markup.length|fun(): markup.length
---@field height? markup.length|fun(): markup.length
---@field min_width? markup.length|fun(): markup.length
---@field max_width? markup.length|fun(): markup.length
---@field min_height? markup.length|fun(): markup.length
---@field max_height? markup.length|fun(): markup.length
---@field margin? markup.edges|fun(): markup.edges
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
---@field overflow? "visible"|"hidden"|fun(): "visible"|"hidden" cuts off what does not fit
---@field overflow_x? "visible"|"hidden"|fun(): "visible"|"hidden" cuts off only what is too wide
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
