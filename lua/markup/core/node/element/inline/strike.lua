local markup = require("markup")

---@class markup.Inline.Strike : markup.Inline
---@field protected super markup.Inline
local Strike = markup.Element:extend("markup.inline.strike") ---@diagnostic disable-line: undefined-field

function Strike:init(...)
    self:_extend_default_props({
        style = { strikethrough = true },
    })
    Strike.super.init(self, ...)
end

---@type markup.Inline.constructor
return Strike
