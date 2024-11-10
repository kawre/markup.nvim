local markup = require("markup")

---@class markup.Inline.Strike : markup.Inline
---@field protected super markup.Inline
local Strike = markup.Element:extend("markup.inline.strike") ---@diagnostic disable-line: undefined-field

function Strike:after_init()
    self._.style.strikethrough = true
end

---@type markup.Inline.constructor
return Strike
