local markup = require("markup")

---@class markup.Inline.Strong : markup.Inline
---@field protected super markup.Inline
local Strong = markup.Element:extend("markup.inline.strong") ---@diagnostic disable-line: undefined-field

function Strong:after_init()
    self._.style.bold = true
end

---@type markup.Inline.constructor
return Strong
