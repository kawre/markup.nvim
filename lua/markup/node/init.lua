local normalizer = require("markup.node.normalizer")

---@alias markup.node.type "element" | "text"

---@class markup.node.props
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
---@field on_confirm? function
---@field on_key? table<string, function>

---@class markup.node
---@field renderer markup.renderer
---@field tag_name string
---@field text_content string
---@field parent markup.node
---@field child_nodes markup.node[]
---@field box? markup.box
---@field fiber markup.fiber
---@field props markup.node.props
---@field container markup.renderer
---@overload fun(type: markup.node.type, name?: string, props?: markup.node.props): markup.node
local Node = Markup.object()

---@param type markup.node.type
---@param name? string
---@param props? markup.node.props
function Node:new(type, name, props)
	self.child_nodes = {}
	self.parent = nil
	self.type = type
	local reconciler = Markup.reconciler.static.get()
	self.container = reconciler and reconciler.renderer
	self.tag_name = name
	self:create_props_proxy(props)
	self.__id = Markup.util.gen_id()
end

---@private
---@param props markup.node.props
function Node:create_props_proxy(props)
	self.props = normalizer.props(props)

	if self.props.on_confirm then
		self.container:subscribe("confirm", self, self.props.on_confirm)
	elseif self.props.on_key then
		for key, cb in pairs(self.props.on_key) do
			vim.keymap.set("n", Markup.util.normkey(key), function()
				cb(self.container)
			end)
			-- self.container:subscribe("key", self, function(ev)
			-- 	if ev.key == key then
			-- 		cb(ev)
			-- 	end
			-- end)
		end
	end

	setmetatable(self.props, {
		__newindex = function(tbl, key, value)
			self:flag_render_tree_as_dirty()
			rawset(tbl, key, value)
		end,
	})
end

---@param props markup.node.props
function Node:replace_props(props)
	self:create_props_proxy(props)
	self:flag_render_tree_as_dirty()
end

---@private
function Node:flag_render_tree_as_dirty()
	if self.box then
		self.box:flag_as_dirty()
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
---@param child markup.node
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
	self:flag_render_tree_as_dirty()
end

---@param child markup.node
function Node:append_child(child)
	self:_insert(child)
end

---@param child markup.node
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

---@param child markup.node
function Node:prepend_child(child)
	self:_insert(child, 1)
end

---@param child markup.node
function Node:remove_child(child)
	for i, node in ipairs(self.child_nodes) do
		if node == child then
			child.parent = nil
			table.remove(self.child_nodes, i)
			break
		end
	end
end

---@param old markup.node
---@param new markup.node
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

---@param event string
---@param cb function
function Node:on(event, cb)
	assert(self.container, "Node must have a container to register event handlers")
	self.container:subscribe(event, self, cb)
end

---@param type markup.node.type
function Node:is(type)
	return self.type == type
end

return Node
