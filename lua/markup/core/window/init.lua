local Object = require("markup.core.object")

---@class markup.Window.props
---@field winid integer
---@field bufnr integer
---@field child markup.Element

---@class markup.Window : markup.Object
---@field _ markup.Window.props
local Window = Object("MarkupWindow")

---@class markup.Window.constructor.props
---@field winid integer
---@field bufnr integer
---@field child markup.Element

---@alias markup.Window.constructor fun(props: markup.Window.constructor.props): markup.Window

---@type markup.Window.constructor
local MarkupWindow = Window

return MarkupWindow
