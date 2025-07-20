local log = require("markup.logger") ---@diagnostic disable-line: unused-local
local u = require("markup.utils")
local normalizer = require("markup.core.node.normalizer")
local _type = type

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
---@field justify? markup.Box.justify
---@field align? markup.Box.align
---@field spacing? markup.Box.spacing
---@field vertical? boolean
---@field horizontal? boolean
---@field sizing? "outer"|"inner"
---@field reverse? boolean
---@field on_confirm? fun()
---@field on_key? table<string, fun()>

---@class markup.Node
---@field renderer markup.Renderer
---@field tag_name string
---@field text_content string
---@field parent markup.Node
---@field child_nodes markup.Node[]
---@field render_box? markup.Render.Box
---@field fiber markup.Fiber
local Node = {}
Node.__index = Node

---@param type markup.Node.type
---@param name? string
---@param props? markup.Node.props
function Node:new(type, name, props)
	self = setmetatable({}, Node)

	self.child_nodes = {}
	self.parent = nil
	self.type = type
	self.tag_name = name
	self:create_props_proxy(props)

	if Markup.is_dev then
		self.__id = u.gen_id()
	end

	return self
end

---@private
---@param props markup.Node.props
function Node:create_props_proxy(props)
	self.props = normalizer.props(props)
	setmetatable(self.props, {
		__newindex = function(tbl, key, value)
			self:flag_render_tree_as_dirty()
			rawset(tbl, key, value)
		end,
	})
end

---@param props markup.Node.props
function Node:replace_props(props)
	self:create_props_proxy(props)
	self:flag_render_tree_as_dirty()
end

---@private
function Node:flag_render_tree_as_dirty()
	if self.render_box then
		self.render_box:flag_as_dirty()
	end
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

---@private
---@param child markup.Node
function Node:_insert(child, pos)
	if pos then
		table.insert(self.child_nodes, pos, child)
	else
		table.insert(self.child_nodes, child)
	end
	if child.parent then
		child.parent:remove_child(child)
	end
	child.parent = self
end

---@param child markup.Node
function Node:append_child(child)
	self:_insert(child)
end

---@param child markup.Node
function Node:insert_before(child)
	local index = 1
	for i, node in ipairs(self.parent.child_nodes) do
		if node == self then
			index = i
			break
		end
	end

	self.parent:_insert(child, index)
end

---@param child markup.Node
function Node:prepend_child(child)
	self:_insert(child, 1)
end

---@param child markup.Node
function Node:remove_child(child)
	for i, node in ipairs(self.child_nodes) do
		if node == child then
			child.parent = nil
			table.remove(self.child_nodes, i)
			break
		end
	end
end

---@param old markup.Node
---@param new markup.Node
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

function Node:destroy()
	assert(self.parent, "Cannot destroy a node without a parent")
	self.parent:remove_child(self)
	self = nil
end

---@param type markup.Node.type
function Node:is(type)
	return self.type == type
end

return Node
