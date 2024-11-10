local markup = require("markup")

---@class markup.Inline.Underline : markup.Inline
---@field protected super markup.Inline
local Underline = markup.Element:extend("markup.inline.underline") ---@diagnostic disable-line: undefined-field

function Underline:after_init()
    self._.style.underline = true
end

---@type markup.Inline.constructor
return Underline
