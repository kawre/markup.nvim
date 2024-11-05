local markup = require("markup")

---@class markup.Padding : markup.Text
local Padding = markup.Text:extend("MarkupPadding") ---@diagnostic disable-line

---@param props markup.Padding.constructor.props
function Padding:init(props)
    Padding.super.init(self, (" "):rep(props or 1), "ErrorMsg")
end

---@alias markup.Padding.constructor.props integer?

---@alias markup.Padding.constructor fun(props: markup.Padding.constructor.props): markup.Padding

---@type markup.Padding.constructor
local MarkupPadding = Padding ---@diagnostic disable-line

return MarkupPadding
