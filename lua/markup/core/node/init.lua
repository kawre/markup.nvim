local log = require("markup.logger") ---@diagnostic disable-line: unused-local
local _type = type
local Factory = require("markup.core.factory.node")

---@alias markup.Node.type "element" | "text"

---@class markup.Node.props
---@field children? markup.factory.Element.constructor.props
---@field style? markup.factory.Element.constructor.style
---@field display? markup.Element.display
---@field padding? markup.Element.padding
---@field padding_top? integer
---@field padding_right? integer
---@field padding_bottom? integer
---@field padding_left? integer
---@field margin? markup.Element.margin
---@field margin_top? integer
---@field margin_right? integer
---@field margin_bottom? integer
---@field margin_left? integer
---@field align? markup.Box.align
---@field spacing? markup.Box.spacing
---@field vertical? boolean
---@field horizontal? boolean
---@field reverse? boolean
---@field on_confirm? fun()
---@field on_key? table<string, fun()>

---@class markup.Node
---@field tag_name string
---@field text_content string
---@field renderer markup.Renderer
---@field render_box? markup.Render.Node
---@field child_nodes markup.Node[]
---@field fiber markup.Fiber
local Node = {}
Node.__index = Node

---@param type markup.Node.type
---@param name? string
---@param props? markup.Node.props
function Node:new(type, name, props)
	local instance = setmetatable({}, self)
	if
		props
		and _type(props) == "table"
		and (_type(props.children) == "string" or _type(props.children) == "number")
	then
		instance.child_nodes = { Factory.create_from_text(props.children) }
	else
		instance.child_nodes = {}
	end

	instance.parent = nil
	instance.type = type
	instance.tag_name = name
	-- instance.props = props

	instance.props = {}
	instance._props = vim.deepcopy(props) or {}
	instance._props.children = nil -- not needed anymore
	setmetatable(instance.props, {
		__index = instance._props,
		__newindex = function(_, key, value)
			if self.render_box then
				self.render_box:flag_as_dirty()
			end
			instance._props[key] = value
		end,
	})

	return instance
end

function Node:set_text_content(content)
	assert(self:is("text"), "Cannot set text content on a non-text node")
	self.text_content = content
end

function Node:clone()
	return vim.deepcopy(self)
end

function Node:has_child_nodes()
	return #self.child_nodes > 0
end

function Node:append_child(child)
	child.parent = self
	table.insert(self.child_nodes, child)
end

function Node:prepend_child(child)
	child.parent = self
	table.insert(self.child_nodes, 1, child)
end

function Node:remove_child(child)
	for i, node in ipairs(self.child_nodes) do
		if node == child then
			child.parent = nil
			table.remove(self.child_nodes, i)
			break
		end
	end
end

function Node:replace_child(old, new)
	for i, node in ipairs(self.child_nodes) do
		if node == old then
			old.parent = nil
			new.parent = self
			self.child_nodes[i] = new
			break
		end
	end
end

---@param _type markup.Node.type
function Node:is(_type)
	return self.type == _type
end

return Node
