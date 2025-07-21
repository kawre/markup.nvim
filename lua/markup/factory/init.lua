---@class markup.factory
local M = {}

M.element = require("markup.factory.element")
M.fiber = require("markup.factory.fiber")
M.node = require("markup.factory.node")
M.box = require("markup.factory.box")
M.renderer = require("markup.factory.renderer")

return M
