local Element = require("nui.element")

---@class NuiEndline : NuiElement
local Endline = Element:extend("ElementEndline")

function Endline:draw(body)
    body:row(1)
end

---@alias NuiEndline.constructor fun(): NuiEndline
---@type NuiEndline|NuiEndline.constructor
local ElementEndline = Endline

return ElementEndline
