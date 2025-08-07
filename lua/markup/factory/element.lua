local Element = require("markup.element")

---@alias markup.factory.element.style string|vim.api.keyset.highlight

---@class markup.factory.element.children.dynamic
---@field [number] markup.factory.element.children

---@alias markup.factory.element.children number|string|table|markup.factory.element.children.dynamic

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

			for key, value in pairs(props) do
				if type(key) == "number" then
					if not new_props.children then
						new_props.children = {}
					end
					table.insert(new_props.children, value)
				else
					new_props[key] = value
				end
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
	if style then
		props = props or {}
		props.style = style
	end

	return Markup.core.create_lsx(type, props)
	-- return Element.new(type, resolve(props, style))
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
