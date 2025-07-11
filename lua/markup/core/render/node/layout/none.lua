local LayoutStrategy = require("markup.core.render.node.layout")

---@class markup.Render.Layout.None : markup.Render.Layout
local NoneLayout = {}
NoneLayout.__index = NoneLayout
setmetatable(NoneLayout, { __index = LayoutStrategy })

function NoneLayout:layout() end

return NoneLayout
