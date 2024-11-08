local markup = require("markup")
local u = require("markup.utils") ---@diagnostic disable-line: unused-local

---@class markup.Node.props
---@field type markup.Node.type

---{ABSTRACT}
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
    self._ = self:_normalize_props(props)
end

---------------------------------
---- Methods (Private)
---------------------------------

---@protected
---@param props any
---@param defaults? markup.Node.props
function Node:_normalize_props(props, defaults)
    return vim.tbl_deep_extend("force", defaults or {}, props)
end

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
    self:_set_state(renderer, parent)

    self:before_render()
    self:render()
    self:after_render()
end

function Node:render()
    error("[Node:render] Method not implemented")
end

function Node:before_render() end

function Node:after_render() end

function Node:is_block()
    return self.display == "block" ---@diagnostic disable-line: undefined-field
end

function Node:is_inline()
    return self.display == "inline" ---@diagnostic disable-line: undefined-field
end

function Node:is_box_item()
    return self.parent and u.is_instance(self.parent, markup.Box)
end

function Node:type()
    return self._.type
end

---@class markup.Node.constructor.props
---@field type markup.Node.type

---@alias markup.Node.constructor fun(props: markup.Node.constructor.props): markup.Node

---@type markup.Node.constructor
local MarkupNode = Node ---@diagnostic disable-line: assign-type-mismatch

return MarkupNode
