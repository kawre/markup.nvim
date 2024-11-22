local markup = require("markup")
local u = require("markup.utils") ---@diagnostic disable-line: unused-local

---@class markup.Node.props
---@field type markup.Node.type

-- {ABSTRACT}
---@class markup.Node : markup.Object
---@field protected _ markup.Node.props
---@field owner markup.Renderer
---@field parent markup.Element
---@field dirty boolean
local Node = markup.Object("markup.node")

---------------------------------
---- Initializer
---------------------------------

---@param props markup.Node.constructor.props
function Node:init(props)
	self._ = props ---@diagnostic disable-line: assign-type-mismatch
	self:after_init()

	self.type = self._.type
end

function Node:after_init() end

---------------------------------
---- Methods (Private)
---------------------------------

function Node:normalize_child_nodes(nodes)
	---@type markup.Node[]
	local tmp = {}
	for _, child in ipairs(nodes) do
		if child:is_type("fragment") then
			---@cast child markup.Fragment
			child:unpack(tmp)
		else
			table.insert(tmp, child)
		end
	end

	local norm, i = {}, 1
	while tmp[i] do
		local node = tmp[i]

		if node:is_type("text") then
			---@cast node markup.Text
			local j = i

			local texts = {}
			while tmp[j] and tmp[j]:is_type("text") do
				table.insert(texts, tmp[j]:content()) ---@diagnostic disable-line: undefined-field
				j = j + 1
			end
			table.insert(norm, markup.Text(table.concat(texts)))
			i = j
		else
			if node:is_type("component") then
				---@cast node markup.Component
				table.insert(norm, node:render())
			else
				table.insert(norm, node)
			end

			i = i + 1
		end
	end

	return norm
end

function Node:normalize_children(children)
	if type(children) == "string" or type(children) == "number" then
		return { markup.Text(children) }
	elseif getmetatable(children) then
		return { children }
	else -- table
		local result = {}

		for _, child in ipairs(children or {}) do
			---@cast child any
			if type(child) == "string" or type(child) == "number" then
				table.insert(result, markup.Text(child))
			elseif getmetatable(child) then
				table.insert(result, child)
			else -- markup.Fragment
				if not vim.tbl_isempty(child) then
					table.insert(result, markup.Fragment(child))
				end
			end
		end

		return result
	end
end

---@protected
---@param renderer markup.Renderer
---@param parent markup.Element
function Node:set_state(renderer, parent)
	self.owner = renderer
	self.parent = parent
end

function Node:prev_sibling()
	if self.parent then
		local idx = self.parent:_index_of(self)
		return idx and self.parent.child_nodes[idx - 1]
	end
end

function Node:next_sibling()
	if self.parent then
		local idx = self.parent:_index_of(self)
		return idx and self.parent.child_nodes[idx + 1]
	end
end

---------------------------------
---- Methods
---------------------------------

---@return markup.Node
function Node:clone()
	return vim.deepcopy(self)
end

---@param renderer markup.Renderer
---@param parent markup.Element
function Node:render_node(renderer, parent)
	self:set_state(renderer, parent)
	self:before_render()
	self:render()
	self:after_render()
end

---@param predicate fun(node: markup.Node): boolean
---@return markup.Node|nil
function Node:find_parent(predicate)
	local node = self.parent

	while node do
		if predicate(node) then
			return node
		end
		node = node.parent
	end

	return nil
end

function Node:render()
	error("[Node:render] Method not implemented")
end

function Node:before_render() end

function Node:after_render() end

---@param kind? string
function Node:is_element(kind)
	local start = "element" .. (kind and "-" .. kind or "")
	return self.type == "element" or u.starts_with(self.type, start)
end

-- Whether new line should be inserted before this node
function Node:is_br()
	---@cast self markup.Element
	return self.computed_display == "block"
		or self.computed_display == "flex"
		or self.computed_display == "grid"
end

---@param type markup.Node.type
function Node:is_type(type)
	return self.type == type
end

function Node:is_block()
	---@cast self markup.Element
	return self.computed_display == "block"
end

-- Whether this node should be treated as a block
function Node:is_block_kind()
	---@cast self markup.Element
	return self.computed_display == "inline-block" or self:is_br()
end

function Node:is_inline()
	---@cast self markup.Element
	return self.computed_display == "inline"
end

-- Whether this node should be treated as an inline
function Node:is_inline_kind()
	---@cast self markup.Element
	return self:is_inline() or u.starts_with(self.computed_display, "inline")
end

function Node:is_flex()
	---@cast self markup.Element
	return self.display == "flex"
end

function Node:is_grid()
	---@cast self markup.Element
	return self.display == "grid"
end

function Node:is_box()
	---@cast self markup.Element
	return self:is_flex() or self:is_grid()
end

function Node:is_box_item()
	local node = self.parent

	while node do
		if node:is_box() then
			return true
		end
		node = node.parent
	end

	return false
end

---@class markup.Node.constructor.props
---@field type markup.Node.type node type

---@alias markup.Node.constructor fun(props: markup.Node.constructor.props): markup.Node

---@type markup.Node.constructor
local MarkupNode = Node ---@diagnostic disable-line: assign-type-mismatch

return MarkupNode
