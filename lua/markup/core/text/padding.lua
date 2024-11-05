local markup = require("markup")

---@class markup.Padding : markup.Text
local Padding = markup.Text:extend("MarkupPadding") ---@diagnostic disable-line

---@param n markup.Padding.constructor.props
function Padding:init(n)
    assert(n and type(n) == "number", "`n` must be a number")
    Padding.super.init(self, (" "):rep(n or 1), "ErrorMsg")
end

---@alias markup.Padding.constructor.props integer?

---@alias markup.Padding.constructor fun(n: markup.Padding.constructor.props): markup.Padding

---@type markup.Padding.constructor
local MarkupPadding = Padding ---@diagnostic disable-line

return MarkupPadding
