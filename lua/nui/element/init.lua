local Object = require("nui.object")
local Style = require("nui.element.style")

---@type table<string, NuiElement>
local Elements = {}

---@class NuiElement.data
---@field style? NuiStyle
---@field id? string
---@field class? string|string[]
---@field content NuiElement[]

---@class NuiElement : NuiObject
---@field _ NuiElement.data
local Element = Object("NuiElement")

---@return NuiStyle.data
function Element:style()
    if not self._.style then
        return {}
    end

    return self._.style:get()
end

---@return string[]
function Element:class()
    if not self._.class then
        return {}
    end

    if type(self._.class) == "string" then
        return { self._.class }
    else
        return self._.class
    end
end

---@return string
function Element:id()
    return self._.id
end

---@param shallow? boolean
---
---@return NuiElement[]
function Element:children(shallow)
    if shallow then
        local children = {}
        for _, child in ipairs(self._.content) do
            table.insert(children, child)
        end
        return children
    else
        return self._.content
    end
end

---@return NuiElement[]
function Element:content()
    local content = self:children()
    return content
end

function Element:endl()
    local Endline = require("nui.element.entity.endline")
    table.insert(self:children(), Endline())
    return self
end

---@param element string|NuiText|NuiLine|NuiElement
---@param highlight? string|nui_text_extmark
function Element:append(element, highlight)
    if type(element) == "string" then
        local Text = require("nui.text")
        element = Text(element, highlight)
    end

    table.insert(self._.content, element)
    return self
end

---@param body NuiBody
---@param parent NuiElement
function Element:draw(body, parent)
    local content = self:children(true)

    local style = self:style()
    if style.padding then
        local endl = require("nui.element.entity.endline")()
        for _ = 1, style.padding[1] do
            table.insert(content, 1, endl)
        end
        for _ = 1, style.padding[3] do
            table.insert(content, endl)
        end
    end

    local row = body:row()

    for _, element in ipairs(content) do
        element:draw(body, self)
    end

    local lines = vim.api.nvim_buf_get_lines(body.bufnr, 0, -1, false)
    if style.padding or style.align then
        local left_pad = 0
        local win_len = vim.api.nvim_win_get_width(body.winid)

        if style.padding then
            left_pad = style.padding[4] - style.padding[2]
        end

        if style.align then
            local longest_line = 0
            for i = row, body:row() do
                longest_line = math.max(longest_line, #lines[i])
            end

            if style.align == "center" then
                left_pad = left_pad + math.floor((win_len - longest_line) / 2)
            end
        end

        for i = row, body:row() do
            local pad = (" "):rep(left_pad)
            if style.align == "right" then
                pad = pad .. (" "):rep(win_len - #lines[i])
            end
            vim.api.nvim_buf_set_text(body.bufnr, i - 1, 0, i - 1, 0, { pad })
        end
    end
end

---@param attributes NuiElement.attributes
function Element:init(attributes, elements)
    local attr = attributes or {}

    if attr.id then
        if Elements[attr.id] then
            error("Element with id " .. attr.id .. " already exists")
        end
        Elements[attr.id] = self
    end

    if attr.style and not Object.is_subclass(attr.style, Style) then
        attr.style = Style(attr.style)
    end

    self._ = {
        style = attr.style,
        id = attr.id,
        class = attr.class,
        content = elements or {},
    }
end

---@class NuiElement.attributes
---@field id? string
---@field style? NuiStyle|table
---@field class? string|string[]

---@alias NuiElement.constructor fun(attributes?: NuiElement.attributes, elements?: NuiElement[]): NuiElement
---@type NuiElement|NuiElement.constructor
local NuiElement = Element

function Element.static:get_by_id(id)
    return Elements[id]
end

return NuiElement
