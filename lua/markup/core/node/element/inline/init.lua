local markup = require("markup")

---@class markup.Inline.props : markup.Element.props

---@class markup.Inline : markup.Element
---@field _ markup.Inline.props
local Inline = markup.Element:extend("markup.inline") ---@diagnostic disable-line: undefined-field

function Inline:after_render()
    for _, child in ipairs(self.children) do
        local prev_sibling = child.prev_sibling
        if prev_sibling and (prev_sibling:is_block() or child:is_block()) then
            self:_newl()
        end

        local lines = child:computed_lines()
        for row, line in pairs(lines) do
            self:_append(line, self:_row() + row)
        end

        if self.vertical == false then
            self:_set_row(0)
        else
            self:_newl(#lines)
        end
    end

    self:_apply_spacing()
end

---@class markup.Inline.constructor.props : markup.Element.constructor.props

---@alias markup.Inline.constructor fun(props?: string | markup.Node | markup.Element.constructor.props, style?: markup.Element.style.props): markup.Element

---@type markup.Element.constructor
local MarkupInline = Inline ---@diagnostic disable-line: assign-type-mismatch

return MarkupInline
