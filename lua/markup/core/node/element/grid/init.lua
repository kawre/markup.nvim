local markup = require("markup")

---@class markup.Grid : markup.Block
---@field protected super markup.Inline
local Grid = markup.Element:extend("markup.grid") ---@diagnostic disable-line: undefined-field

function Grid:init(...)
    self:_extend_default_props({
        display = "grid",
    })
    Grid.super.init(self, ...)
end

function Grid:after_render()
    error("Not implemented")
end

---@alias markup.Grid.constructor markup.Element.constructor

---@type markup.Grid.constructor
return Grid
