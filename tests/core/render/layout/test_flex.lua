---@module 'mini.test'

local helpers = dofile("tests/helpers/init.lua")
local T = MiniTest.new_set()

T["works"] = function()
	local x = 1 + 1
	MiniTest.expect.equality(x, 2)
end

return T
