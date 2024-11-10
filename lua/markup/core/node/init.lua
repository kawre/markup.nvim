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
local Node = markup.Object("MarkupNode")

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

---@protected
---@param renderer markup.Renderer
---@param parent markup.Element
function Node:_set_state(renderer, parent)
    self.owner = renderer
    self.parent = parent

    if parent then
        local node_index = parent:_index_of(self)
        if node_index then
            self.prev_sibling = parent.child_nodes[node_index - 1]
            self.next_sibling = parent.child_nodes[node_index + 1]
        end
    end
end

---------------------------------
---- Methods
---------------------------------

function Node:clone()
    return vim.deepcopy(self)
end

---@param renderer markup.Renderer
---@param parent markup.Element
function Node:render_node(renderer, parent)
    self:before_render(renderer, parent)

    self:_set_state(renderer, parent)
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
    return self.type == start or self.type:sub(1, #start) == start
end

function Node:is_block()
    return self.display == "block" ---@diagnostic disable-line: undefined-field
end

function Node:is_inline()
    return self.display == "inline" ---@diagnostic disable-line: undefined-field
end

function Node:is_box_item()
    local node = self.parent

    while node do
        if u.is_instance(node, markup.Box) then
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
