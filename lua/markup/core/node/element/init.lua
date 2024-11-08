local markup = require("markup")
local utils = require("markup.utils") ---@diagnostic disable-line
local log = require("markup.logger") ---@diagnostic disable-line

---@class markup.Element.props : markup.Node.props
---@field row integer
---@field lines markup.Line[]
---@field style markup.Element.style
---@field children markup.Node[]
---@field display markup.Element.display

---@class markup.Element : markup.Node
---@field protected _ markup.Element.props
---@field protected super markup.Node
---@field display markup.Element.display
---@field child_nodes markup.Node[]
---@field children markup.Element[]
---@field first_child markup.Node
---@field first_element_child markup.Element
---@field last_child markup.Node
---@field last_element_child markup.Element
---@field prev_sibling markup.Node
---@field prev_element_sibling markup.Element
---@field next_sibling markup.Node
---@field next_element_sibling markup.Element
local Element = markup.Node:extend("MarkupElement") ---@diagnostic disable-line: undefined-field

---------------------------------
---- Constructor
---------------------------------

---@param props markup.Element.constructor.props
---@param style? markup.Element.style
function Element:init(props, style)
    props = self:_normalize_props(props, {
        type = "element",
        row = 0,
        lines = {},
        children = {},
        style = {},
        display = "inline",
    })

    Element.super.init(self, props)
end

---------------------------------
---- Methods (Private)
---------------------------------

---@protected
---@param n? integer
---@return markup.Element
function Element:_newl(n)
    self:_inc_row(n or 1)
    self:_fill_lines()
    return self
end

---@protected
---@param row_at? integer (0-indexed)
---@return markup.Line
function Element:_line(row_at)
    row_at = row_at or self:_row()
    self:_fill_lines(row_at)
    return self._.lines[row_at]
end

---@protected
---@param row integer (0-indexed)
function Element:_set_row(row)
    self._.row = row
    return self._.row
end

---@protected
---@return integer (0-indexed)
function Element:_row()
    return self._.row
end

---@protected
---@param row_at? integer (0-indexed)
function Element:_fill_lines(row_at)
    local lines = self._.lines
    for i = #lines, row_at or self:_row() do
        if not lines[i] then
            lines[i] = markup.Line()
        end
    end
end

---@protected
---@param n integer
function Element:_inc_row(n)
    return self:_set_row(self:_row() + n)
end

---@protected
---@param content string|markup.Text|markup.Line
---@param row_at? integer (0-indexed)
---@return markup.Element
function Element:_append(content, row_at)
    self:_line(row_at):append(content)
    return self
end

---@protected
---@param content string|markup.Text|markup.Line
---@param row_at? integer (0-indexed)
---@return markup.Element
function Element:_prepend(content, row_at)
    self:_line(row_at):prepend(content)
    return self
end

---@protected
---@param element markup.Element
function Element:_inherit_style(element)
    if not element then
        return self._.style
    end
    return vim.tbl_deep_extend("force", element.style or element._.style, self._.style)
end

---@protected
---@param element markup.Element
function Element:_inherit_display(element)
    if not element then
        return self._.display
    end

    if utils.is_instance(element, markup.Box) then
        ---@cast element markup.Box
        return element:vertical() and "block" or "inline"
    else
        return self._.display
    end
end

---@protected
---@param props any
---@param defaults any
function Element:_normalize_props(props, defaults)
    local result = {}

    if type(props) == "string" then
        result.children = { markup.Text(props) }
    elseif getmetatable(props) then
        result.children = { props }
    else
        result = props

        if type(props.children) == "string" then
            result.children = { markup.Text(props.children) }
        elseif getmetatable(props.children) then
            result.children = { props.children }
        end
    end

    return vim.tbl_deep_extend("force", defaults or {}, result)
end

---@param child markup.Node
function Element:_index_of(child)
    return utils.index_of(self.child_nodes, child)
end

---@param child markup.Element
function Element:_index_of_element(child)
    return utils.index_of(self.children, child)
end

---@protected
---@param renderer markup.Renderer
---@param parent markup.Element
function Element:_set_state(renderer, parent)
    Element.super._set_state(self, renderer, parent)

    self._.row = 0
    self._.lines = {}
    self.display = self:_inherit_display(parent)
    self.style = self:_inherit_style(parent)
    self.child_nodes = self._.children
    self.children = vim.tbl_filter(function(child)
        return child:type() == "element"
    end, self.child_nodes)

    self.last_child = self.child_nodes[#self.child_nodes]
    self.first_child = self.child_nodes[1]
    self.first_element_child = self.children[1]
    self.last_element_child = self.children[#self.children]

    if parent then
        local node_index = parent:_index_of(self)
        if node_index then
            self.prev_sibling = parent.child_nodes[node_index - 1]
            self.next_sibling = parent.child_nodes[node_index + 1]
        end

        local element_index = parent:_index_of_element(self)
        if element_index then
            self.prev_element_sibling = parent.children[element_index - 1]
            self.next_element_sibling = parent.children[element_index + 1]
        end
    end
end

---------------------------------
---- Methods
---------------------------------

---@param child markup.Node
function Element:append_child(child)
    table.insert(self.child_nodes, child)
    return child
end

---@param other_node markup.Node
function Element:contains(other_node)
    return utils.index_of(self.child_nodes, other_node) ~= nil
end

---@param node markup.Node
function Element:insert_before(node)
    local index = utils.index_of(self.child_nodes, node)
    assert(index, "node not found")
    table.insert(self.child_nodes, index, node)
    return node
end

---@param child markup.Node
function Element:remove_child(child)
    local index = utils.index_of(self.child_nodes, child)
    assert(index, "child not found")
    return table.remove(self.child_nodes, index)
end

function Element:replace_child(new_child, old_child)
    local index = utils.index_of(self.child_nodes, old_child)
    assert(index, "child not found")
    self.child_nodes[index] = new_child
    return old_child
end

function Element:render()
    for _, child in ipairs(self.child_nodes) do
        child:render_node(self.owner, self)
    end
end

function Element:after_render()
    for _, child in ipairs(self.children) do
        local prev_sibling = child.prev_sibling

        if prev_sibling and (prev_sibling:is_block() or child:is_block()) then
            self:_newl()
        end

        local lines = child:computed_lines()
        for row, line in pairs(lines) do
            self:_append(line, self:_row() + row)
        end

        if child:vertical() then
            self:_set_row(0)
        else
            self:_newl(#lines)
        end
    end
end

---@return integer
function Element:width()
    local max_len = 0
    for _, line in pairs(self._.lines) do
        max_len = math.max(max_len, line:length())
    end
    return max_len
end

---@return integer
function Element:height()
    local h = 0
    for _ in pairs(self._.lines) do
        h = h + 1
    end
    return h
end

---@return integer, integer
function Element:size()
    return self:width(), self:height()
end

---@return integer, integer
function Element:box_size()
    if self.parent then
        return self:size()
    else
        return self.owner:width(), self.owner:height()
    end
end

function Element:max_size()
    local children = self.children

    local max_width, max_height = 0, 0
    for _, child in ipairs(children) do
        max_height = math.max(max_height, child:height())
        max_width = math.max(max_width, child:width())
    end

    return max_width, max_height
end

function Element:computed_style()
    return self.style
end

function Element:computed_lines()
    return self._.lines
end

function Element:is_block()
    return self.display == "block"
end

function Element:is_inline()
    return self.display == "inline"
end

---------------------------------
---- Initializer
---------------------------------

---@class markup.Element.constructor.props : markup.Node.constructor.props
---@field children? string|markup.Node|markup.Node[]
---@field style? markup.Element.style
---@field display? markup.Element.display

---@alias markup.Element.style.props string|markup.Element.style

---@alias markup.Element.constructor fun(props?: string | markup.Node | markup.Element.constructor.props, style?: markup.Element.style.props): markup.Element

---@type markup.Element.constructor
local MarkupElement = Element ---@diagnostic disable-line

return MarkupElement
