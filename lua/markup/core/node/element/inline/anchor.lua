local markup = require("markup")

---@class markup.Inline.Anchor : markup.Inline
---@field protected super markup.Inline
local Anchor = markup.Element:extend("markup.inline.anchor") ---@diagnostic disable-line: undefined-field

function Anchor:after_init()
    Anchor.super.after_init(self)

    self._.style = {
        underline = true,
        fg = "#89b4fb",
    }
end

---@type markup.Inline.constructor
return Anchor
