---@class markup.collection
---@field stack markup.stack
---@field array markup.array
local M = {}

M.stack = require("markup.collection.stack")
M.array = require("markup.collection.array")

return M
