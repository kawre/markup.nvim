local markup = require("markup")

---@class markup.Inline.Italic : markup.Inline
---@field protected super markup.Inline
local Italic = markup.Element:extend("markup.inline.italic") ---@diagnostic disable-line: undefined-field

function Italic:after_init()
    self._.style.italic = true
end

---@type markup.Inline.constructor
return Italic
