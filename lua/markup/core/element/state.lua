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
        parent = parent,
        element = element,
    }
end

---@param row_at? integer (0-indexed)
---@return markup.Line
function State:get_line(row_at)
    row_at = row_at or self._.row

    local lines = self:get_lines()
    for i = self._.row, row_at do
        if not lines[i] then
            lines[i] = markup.Line()
        end
    end

    return lines[row_at]
end

function State:append_line(line, row_at)
    for _, text in ipairs(line:get_texts()) do
        self:get_line(row_at):append(text)
    end

    return self
end

function State:endl(n)
    self._.row = self._.row + (n or 1)
    return self
end

function State:set_row(row)
    self._.row = row
    return self
end

function State:get_row()
    return self._.row
end

function State:append_text(text)
    self:get_line():append(text)
    return self
end

function State:print_lines()
    local lines = "\""
    for i, line in pairs(self:get_lines()) do
        lines = lines .. line:content() .. "\"\n\""

        if i == #self:get_lines() then
            lines = lines .. "---"
        end
    end

    log.debug(lines)
end

---@return table<integer, markup.Line> (0-indexed)
function State:get_lines()
    return self._.lines
end

---@param row_at? integer (0-indexed)
---@return markup.Text[]
function State:get_texts(row_at)
    return self:get_line(row_at):get_texts()
end

---@return markup.Element[]
function State:get_children()
    return vim.tbl_filter(function(child)
        return not utils.is_instance(child, markup.Text)
    end, self._.element:get_children())
end

---@return markup.Element
function State:get_prev_sibling()
    local parent = self._.parent

    if parent then
        local children = parent:get_children()
        local index = utils.index_of(children, self._.element)
        return children[index - 1]
    end
end

function State:get_width()
    local max_len = 0
    for _, line in pairs(self:get_lines()) do
        max_len = math.max(max_len, line:length())
    end
    return max_len
end

function State:get_height()
    local h = 0
    for _ in pairs(self:get_lines()) do
        h = h + 1
    end
    return h
end

function State:get_size()
    return self:get_width(), self:get_height()
end

function State:get_direction()
    local element = self._.element --[[@as markup.Box]]
    return element._.direction
end

function State:get_align()
    local element = self._.element --[[@as markup.Box]]
    return element._.align
end

function State:is_box()
    return self:get_direction() ~= nil
end

-- ---@param node markup.Element
-- ---@param renderer markup.Renderer
-- function State:merge_node(node, renderer)
-- end

-- ---@param renderer markup.Renderer
-- function State:merge_centered(renderer)
--     local max_len = self:get_width()
--     for _, line in pairs(self:get_lines()) do
--         local padding = math.floor((max_len - line:length()) / 2)
--         self:get_line():append(markup.Padding(padding))
--         for _, text in ipairs(line:get_texts()) do
--             self:get_line():append(text)
--         end
--         self:get_line():append(markup.Padding(padding))
--     end
-- end

---@param renderer markup.Renderer
function State:get_type(renderer)
    local parent_state = renderer:get_state(self:get_parent())
    local dir = parent_state:get_direction()

    if dir == "column" then
        return "block"
    elseif dir == "row" then
        return "inline"
    else
        return self._.element._.type
    end
end

function State:get_parent()
    return self._.parent
end

---@class markup.Element.State.constructor.props
---@field parent_element markup.Element
---@field children markup.Element[]
---@field style markup.Element.style

---@alias markup.Element.State.constructor fun(element: markup.Element, parent: markup.Element): markup.Element.State

---@type markup.Element.State.constructor
local MarkupElementState = State

return MarkupElementState
