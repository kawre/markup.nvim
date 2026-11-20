local eq = MiniTest.expect.equality
local T = MiniTest.new_set()

T["supports checks the installed release against the client range"] = function()
	local config = dofile("lua/markup/config.lua")
	for version, expected in pairs({
		["0.1.9"] = false,
		["0.2.0"] = true,
		["0.2.7"] = true,
		["0.3.0"] = false,
	}) do
		config.version = version
		eq(config.supports("^0.2"), expected)
	end
end

return T
