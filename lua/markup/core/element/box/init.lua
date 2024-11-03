local markup = require("markup")
local utils = require("markup.utils")
local log = require("markup.logger")

---@alias markup.Box.align "start"|"center"|"end"
---@alias markup.Box.direction "row"|"column"
---@alias markup.Box.spacing string|integer

---@class markup.Box.props : markup.Element.props
---@field align markup.Box.align
---@field spacing markup.Box.spacing
---@field direction markup.Box.direction

---@class markup.Box : markup.Element
---@field _ markup.Box.props
local Box = markup.Block:extend("MarkupBox")

function Box:init(props)
    props = self:normalize_props(props, {
        align = "start",
        direction = "column",
        spacing = 0,
    })

    Box.super.init(self, props)
end

---@param renderer markup.Renderer
function Box:draw(renderer)
    local state = renderer:get_state(self)
    local content = self:content()
    local dir = self:get_direction()
    local type = dir == "column" and "block" or "inline"
    local spacing = self:get_spacing()

    for i, element in ipairs(content) do
        element:with_type(type, function()
            element:render(renderer, self)
        end)

        local child_state = renderer:get_state(element)
        renderer:get_current_element_range(element)
        -- if dir == "row" then
        -- 	state = renderer:get_state(self)
        --
        -- 	if child_state.row_end < state.row_end then
        -- 		state.row_start = child_state.row_start
        -- 	end
        -- end

        if i ~= #content then
            if spacing > 0 then
                if dir == "column" then
                    renderer:endl(spacing)
                elseif dir == "row" then
                    -- local child_state = renderer:get_state(element)
                    for j = child_state.row_start, child_state.row_end do
                        renderer:pad(spacing, j)
                    end
                end
            end
            if dir == "row" then
                renderer:set_pos(state.initial.row)
            end
        end
    end
end

---@param renderer markup.Renderer
function Box:after_draw(renderer)
    local state = renderer:get_state(self)
    local align, dir = self:get_align(), self:get_direction()

    for row = state.row_start, state.row_end do
        local length = state.lengths[row]
        local padding = state.box.width - length

        if align == "start" then
            renderer:pad(padding, row)
        elseif align == "center" then
            local half_padding = math.floor(padding / 2)
            renderer:pad(half_padding, row, state.col_start)
            renderer:pad(half_padding + padding % 2, row)
        elseif align == "end" then
            renderer:pad(padding, row, state.col_start)
        end
    end

    if dir == "row" then
        renderer:reset_pos()
    end

    Box.super.after_draw(self, renderer)
end

function Box:get_spacing()
    return tonumber(self._.spacing)
end

function Box:get_align()
    return self._.align
end

function Box:get_direction()
    return self._.direction
end

---@class markup.Box.constructor.props
---@field children markup.Element[]
---@field spacing? markup.Box.spacing
---@field align? markup.Box.align
---@field direction? markup.Box.direction

---@alias markup.Box.constructor fun(props?: markup.Element | markup.Box.constructor.props): markup.Box

---@type markup.Box.constructor
local MarkupBox = Box

return MarkupBox
