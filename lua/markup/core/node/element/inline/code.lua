local markup = require("markup")

---@class markup.Inline.Code : markup.Inline
---@field protected super markup.Inline
local Code = markup.Element:extend("markup.inline.Code") ---@diagnostic disable-line: undefined-field

function Code:after_init()
    Code.super.after_init(self)

    self._.style.color = "#f2cdce"
end

---@type markup.Inline.constructor
return Code
