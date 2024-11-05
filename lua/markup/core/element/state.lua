local markup = require("markup")
local log = require("markup.logger") ---@diagnostic disable-line
local utils = require("markup.utils") ---@diagnostic disable-line

MRKUP = {}

---@alias markup.Node markup.Element|markup.Text

---@class markup.Element.State : markup.Object
---@field row integer
---@field lines table<integer, markup.Line>
---@field parent markup.Element
---@field children markup.Element[]
---@field child_nodes markup.Node[]
---@field prev_sibling markup.Element
---@field first_child markup.Element
---@field last_child markup.Element
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
function State:init(element, parent)
    self.row = 0
    self.lines = {}
    self.parent = parent
    self.element = element

    local children = element:children()

    self.first_child = children[1]
    self.last_child = children[#children]

    self.children = vim.tbl_filter(function(child)
        return not utils.is_instance(child, markup.Text)
    end, children)
    self.child_nodes = children

    self.align = element.align and element:align() ---@diagnostic disable-line
    self.direction = element.direction and element:direction() ---@diagnostic disable-line
    self.spacing = element.spacing and element:spacing() ---@diagnostic disable-line

    if parent then
        local parent_children = parent:children()
        local index = utils.index_of(parent_children, element)
        self.prev_sibling = parent_children[index - 1]

        local parent_dir = parent.direction and parent:direction() ---@diagnostic disable-line
        self.type = parent_dir and (parent_dir == "column" and "block" or "inline")
            or element:type()
    end
end

---------------------------------
---- Methods
---------------------------------

---@param n? integer
function State:endl(n)
    self.row = self.row + (n or 1)
    return self
end

---@param n? integer
function State:newl(n)
    self:endl(n)
    self:line()
    return self
end

---@param text markup.Text
---@return markup.Element.State
function State:append_text(text)
    self:line():append(text)
    return self
end

---@param line markup.Line
---@param row_at? integer (0-indexed)
function State:append_line(line, row_at)
    for _, text in ipairs(line:texts()) do
        self:line(row_at):append(text)
    end

    return self
end

function State:print_lines()
    local lines = "----\n"
    for _, line in pairs(self.lines) do
        lines = lines .. line:content() .. "\n"
    end
    lines = lines .. "----"
    log.debug(lines)
end

---------------------------------
---- Setters
---------------------------------

---@param row integer (0-indexed)
function State:set_row(row)
    self.row = row
    return self
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

    local lines = self.lines
    for i = #lines, row_at do
        if not lines[i] then
            lines[i] = markup.Line()
        end
    end

    return lines[row_at]
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

---@param renderer markup.Renderer
function State:max_size(renderer)
    local children = self.children

    local max_width, max_height = 0, 0
    for _, child in ipairs(children) do
        local child_state = renderer:state(child)
        max_height = math.max(max_height, child_state:height())
        max_width = math.max(max_width, child_state:width())
    end

    return max_width, max_height
end

function State:size()
    return self:width(), self:height()
end

---@param renderer markup.Renderer
function State:box_size(renderer)
    if self.parent then
        return self:size()
    else
        return renderer:width(), renderer:height()
    end
end

---------------------------------
---- Initializer
---------------------------------

---@alias markup.Element.State.constructor fun(element: markup.Element, parent: markup.Element): markup.Element.State

---@type markup.Element.State.constructor
local MarkupElementState = State ---@diagnostic disable-line

return MarkupElementState
