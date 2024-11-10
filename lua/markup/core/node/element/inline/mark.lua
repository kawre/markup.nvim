local markup = require("markup")

---@class markup.Inline.Mark : markup.Inline
---@field protected super markup.Inline
local Mark = markup.Element:extend("markup.inline.mark") ---@diagnostic disable-line: undefined-field

function Mark:after_init()
    self._.style.background = "yellow"
    self._.style.color = "black"
end

---@type markup.Inline.constructor
return Mark
