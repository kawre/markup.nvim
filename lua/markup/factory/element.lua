local Element = require("markup.element")

---@alias markup.factory.element.props.children
---| string
---| number
---| table

---@alias markup.factory.element.style
---| string
---| vim.api.keyset.highlight

---@alias markup.factory.element.props
---| markup.factory.element.props.children
---| { children?: markup.factory.element.props.children }
---| markup.node.props

---@alias markup.factory.element.fragment.props
---| markup.factory.element.props.children
---| { children?: markup.factory.element.props.children }

---@alias markup.factory.element
---| fun(props?: markup.factory.element.props, style?: markup.factory.element.style): markup.element

---@alias markup.factory.element.fragment
---| fun(props?: markup.factory.element.fragment.props): markup.element

---@alias markup.factory.element.component
---| fun(props?: any|{ children?: any }): any

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

--@type markup.factory.Element.constructor.raw
function M.call(type, props, style)
	return Element.new(type, resolve(props, style))
end

function M.component(Component)
	return function(...)
		return M.call(Component, ...)
	end
end

---@param Class table
function M.class(Class)
	return function(...)
		Class.typeof = "class"
		return M.call(Class, ...)
	end
end

function M.fragment(...)
	return M.call("fragment", ...)
end

return M
