---@module 'mini.test'
---@module 'markup'

local markup = require("markup")
local new_set = MiniTest.new_set
local expect, eq = MiniTest.expect, MiniTest.expect.equality
local Factory = require("markup.core.factory.fiber")

local T = new_set()

-- T['']

return T
