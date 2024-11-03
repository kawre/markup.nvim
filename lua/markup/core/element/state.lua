local markup = require("markup")
local log = require("markup.logger")
local utils = require("markup.utils")

---@class markup.Element.State : markup.Object
---@field lines table<integer, markup.Line>
---@field row integer
---@field parent_element markup.Element
---@field children markup.Element[]
---@field type markup.Element.type
---@field style markup.Element.style
local State = markup.Object("MarkupElementState")

---@param element markup.Element
---@param parent markup.Element
function State:init(element, parent)
    self._ = {
        row = 0,
        lines = {},
        parent_element = parent,
        -- children = utils.shallow_copy(element:get_children()),
        children = element:get_children(),
        type = element:get_type(),
        element = element,
    }
end

function State:get_row()
    return self._.row
end

---@return markup.Line
function State:get_line(row_at)
    row_at = row_at or self:get_row()

    if not self._.lines[row_at] then
        self._.lines[row_at] = markup.Line()
    end

    return self._.lines[row_at]
end

---@param n? integer
function State:inc_row(n)
    self._.row = self._.row + (n or 1)
end

function State:append_text(text)
    self:get_line():append(text)
    return self
end

---@return markup.Line[]
function State:get_lines()
    return self._.lines
end

---@return markup.Text[]
function State:get_texts(row_at)
    return self:get_line(row_at):get_texts()
end

---@return markup.Element[]
function State:get_children()
    return self._.children
end

function State:get_prev_sibling()
    local parent = self._.parent_element
    if parent then
        local children = parent:get_children()
        local index = utils.index_of(children, self._.element)
        return children[index - 1]
    end
end

function State:get_type()
    local parent = self._.parent_element
    if parent and parent.get_direction then
        return parent:get_direction() == "column" and "block" or "inline"
    else
        return self._.type
    end
end

---@class markup.Element.State.constructor.props
---@field parent_element markup.Element
---@field children markup.Element[]
---@field style markup.Element.style

---@alias markup.Element.State.constructor fun(element: markup.Element, parent: markup.Element): markup.Element.State

---@type markup.Element.State.constructor
local MarkupElementState = State

return MarkupElementState
