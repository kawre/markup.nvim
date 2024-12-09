local log = require("markup.logger") ---@diagnostic disable-line: unused-local
local enum = require("markup.core.enum")

---@class markup.core
local core = enum.bind(enum.Lookup)
core.Render = enum.bind(enum.Render)

return core
