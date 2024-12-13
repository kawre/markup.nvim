local log = require("markup.logger") ---@diagnostic disable-line: unused-local
local enum = require("markup.core.enum")

---@class markup.core
---@field public Render markup.core.Lookup.Render
local core = enum:bind()

return core
