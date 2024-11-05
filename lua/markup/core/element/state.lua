local markup = require("markup")
local log = require("markup.logger") ---@diagnostic disable-line
local utils = require("markup.utils") ---@diagnostic disable-line

---@alias markup.Node markup.Element|markup.Text

---@class markup.Element.State : markup.Object
---@field parent markup.Element
---@field children markup.Element[]
---@field renderer markup.Renderer
---@field row integer
---@field lines table<integer, markup.Line>
---@field child_nodes markup.Node[]
---@field prev_sibling markup.Node
---@field prev_element_sibling markup.Element
---@field first_child markup.Node
---@field first_element_child markup.Element
---@field last_child markup.Node
---@field last_element_child markup.Element
---@field type markup.Element.type
---@field style markup.Element.style
---@field align markup.Box.align
---@field direction markup.Box.direction
local State = markup.Object("MarkupElementState")

---------------------------------
---- Initializer
---------------------------------

---@param element markup.Element
---@param parent markup.Element
---@param renderer markup.Renderer
function State:init(element, parent, renderer)
    self.row = 0
    self.lines = {}
    self.parent = parent
    self.element = element
    self.renderer = renderer

    local children = utils.shallow_copy(element:children())
    local child_nodes = utils.shallow_copy(element:child_nodes())

    self.first_child = child_nodes[1]
    self.first_element_child = children[1]

    self.last_child = child_nodes[#child_nodes]
    self.last_element_child = children[#children]

    self.children = children
    self.child_nodes = child_nodes

    self.align = element.align and element:align() ---@diagnostic disable-line
    self.direction = element.direction and element:direction() ---@diagnostic disable-line
    self.spacing = element.spacing and element:spacing() ---@diagnostic disable-line
    self.type = element:type()
    self.style = element:style()

    if parent then
        local parent_state = renderer:state(parent)

        local parent_children = parent_state.children
        local parent_child_nodes = parent_state.child_nodes

        local n_index = utils.index_of(parent_child_nodes, element)
        self.prev_sibling = parent_child_nodes[n_index - 1]
        self.next_sibling = parent_child_nodes[n_index + 1]
        local e_index = utils.index_of(parent_children, element)
        self.prev_element_sibling = parent_children[e_index - 1]
        self.next_element_sibling = parent_children[e_index + 1]

        local parent_dir = parent.direction and parent:direction() ---@diagnostic disable-line
        self.type = parent_dir and (parent_dir == "column" and "block" or "inline") or self.type
        self.style = vim.tbl_deep_extend("force", parent_state.style, self.style)
    end
end

---------------------------------
---- Methods
---------------------------------

---@param n? integer
function State:newl(n)
    self:inc_row(n or 1)
    self:fill_lines()
    return self
end

---@param content string|markup.Text|markup.Line
---@param row_at? integer (0-indexed)
---@return markup.Element.State
function State:append(content, row_at)
    self:line(row_at):append(content)
    return self
end

---@param content string|markup.Text|markup.Line
---@param row_at? integer (0-indexed)
---@return markup.Element.State
function State:prepend(content, row_at)
    self:line(row_at):prepend(content)
    return self
end

---@param row_at? integer (0-indexed)
function State:fill_lines(row_at)
    local lines = self.lines
    for i = #lines, row_at or self.row do
        if not lines[i] then
            lines[i] = markup.Line()
        end
    end
end

---------------------------------
---- Setters
---------------------------------

---@param row integer (0-indexed)
function State:set_row(row)
    self.row = row
    return self.row
end

---@param n integer
function State:inc_row(n)
    return self:set_row(self.row + n)
end

---------------------------------
---- Getters
---------------------------------

---@param row_at? integer (0-indexed)
---@return markup.Text[]
function State:texts(row_at)
    return self:line(row_at):texts()
end

---@param row_at? integer (0-indexed)
function State:line(row_at)
    row_at = row_at or self.row
    self:fill_lines(row_at)
    return self.lines[row_at]
end

---@return integer
function State:width()
    local max_len = 0
    for _, line in pairs(self.lines) do
        max_len = math.max(max_len, line:length())
    end
    return max_len
end

function State:height()
    local h = 0
    for _ in pairs(self.lines) do
        h = h + 1
    end
    return h
end

function State:size()
    return self:width(), self:height()
end

function State:box_size()
    if self.parent then
        return self:size()
    else
        return self.renderer:width(), self.renderer:height()
    end
end

function State:max_size()
    local children = self.children

    local max_width, max_height = 0, 0
    for _, child in ipairs(children) do
        local child_state = self.renderer:state(child)
        max_height = math.max(max_height, child_state:height())
        max_width = math.max(max_width, child_state:width())
    end

    return max_width, max_height
end

function State:is_inline()
    return self.type == "inline"
end

function State:is_block()
    return self.type == "block"
end

function State:is_box()
    return self.direction and true or false
end

---------------------------------
---- Initializer
---------------------------------

---@alias markup.Element.State.constructor fun(element: markup.Element, parent: markup.Element, renderer: markup.Renderer): markup.Element.State

---@type markup.Element.State.constructor
local MarkupElementState = State ---@diagnostic disable-line

return MarkupElementState
