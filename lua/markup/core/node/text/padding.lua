local markup = require("markup")

---@class markup.Padding : markup.Text
---@field protected super markup.Text
local Padding = markup.Text:extend("MarkupPadding") ---@diagnostic disable-line: undefined-field

---@param n markup.Padding.constructor.props
function Padding:init(n, ...)
    Padding.super.init(self, (" "):rep(tonumber(n)), ...) ---@diagnostic disable-line: param-type-mismatch
end

---@alias markup.Padding.constructor.props string|integer

---@alias markup.Padding.constructor fun(n: markup.Padding.constructor.props, parent?: markup.Node): markup.Padding

---@type markup.Padding.constructor
local MarkupPadding = Padding ---@diagnostic disable-line: assign-type-mismatch

return MarkupPadding
