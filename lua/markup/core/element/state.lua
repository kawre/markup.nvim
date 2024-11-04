local markup = require("markup")
local log = require("markup.logger")
local utils = require("markup.utils")

---@alias markup.Node markup.Element|markup.Text

---@class markup.Element.State : markup.Object
---@field private row integer
---@field lines table<integer, markup.Line>
---@field parent markup.Element
---@field children markup.Element[]
---@field child_nodes markup.Node[]
---@field prev_sibling markup.Element
---@field first_child markup.Element
---@field last_child markup.Element
---@field type markup.Element.type
---@field style markup.Element.style
local State = markup.Object("MarkupElementState")

---@param element markup.Element
---@param parent markup.Element
function State:init(element, parent)
    self.row = 0
    self.lines = {}
    self.parent = parent
    self.element = element

    local children = element:children()
    local parent_children = parent:children()

    local index = utils.index_of(parent_children, element)

    self.prev_sibling = parent_children[index - 1]

    self.first_child = children[1]
    self.last_child = children[#children]

    self.children = vim.tbl_filter(function(child)
        return not utils.is_instance(child, markup.Text)
    end, children)
    self.child_nodes = children

    local parent_dir = parent.direction and parent:direction() ---@diagnostic disable-line
    self.type = parent_dir and (parent_dir == "column" and "block" or "inline") or element:type()
end

---@param row_at? integer (0-indexed)
function State:line(row_at)
    row_at = row_at or self.row

    local lines = self.lines
    for i = self.row, row_at do
        if not lines[i] then
            lines[i] = markup.Line()
        end
    end

    return lines[row_at]
end

---@param line markup.Line
---@param row_at? integer (0-indexed)
function State:append_line(line, row_at)
    for _, text in ipairs(line:texts()) do
        self:line(row_at):append(text)
    end

    return self
end

---@param n? integer
function State:endl(n)
    self.row = self.row + (n or 1)
    return self
end

---@param row integer (0-indexed)
function State:set_row(row)
    self.row = row
    return self
end

---@return integer
function State:get_row()
    return self.row
end

---@param text markup.Text
---@return markup.Element.State
function State:append_text(text)
    self:line():append(text)
    return self
end

---@param row_at? integer (0-indexed)
---@return markup.Text[]
function State:texts(row_at)
    return self:line(row_at):texts()
end

---@return integer
function State:width()
    local max_len = 0
    for _, line in pairs(self.lines) do
        max_len = math.max(max_len, line:length())
    end
    return max_len
end

function State:box_size()
    if self.parent then
        return self:get_size()
    else
        return 60, 80
    end
end

function State:height()
    local h = 0
    for _ in pairs(self.lines) do
        h = h + 1
    end
    return h
end

function State:get_size()
    return self:width(), self:height()
end

function State:direction()
    local element = self.element --[[@as markup.Box]]
    return element:direction()
end

function State:align()
    local element = self.element --[[@as markup.Box]]
    return element:align()
end

---@class markup.Element.State.constructor.props
---@field parent_element markup.Element
---@field children markup.Element[]
---@field style markup.Element.style

---@alias markup.Element.State.constructor fun(element: markup.Element, parent: markup.Element): markup.Element.State

---@type markup.Element.State.constructor
local MarkupElementState = State ---@diagnostic disable-line

return MarkupElementState
