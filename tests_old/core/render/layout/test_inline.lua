---@module 'mini.test'

local helpers = dofile("tests/helpers/init.lua")
local expect = MiniTest.expect
local child = MiniTest.new_child_neovim()

local path = "tests/core/render/layout/assets/"
local render = helpers.mock_layout(path, "Inline")

local T = MiniTest.new_set({
	hooks = {
		pre_case = function()
			child.restart({ "-u", "scripts/minimal_init.lua" })
			child.lua([[markup = require('markup')]])
			child.o.lines, child.o.columns = 15, 30
		end,
		post_once = child.stop,
	},
})

T["render()"] = MiniTest.new_set({
	parametrize = {
		{ "inline/numbers.lua" },
		{ "nothing.lua" },
		{ "empty.lua" },
	},
})

T["render()"]["works"] = function(file)
	child.lua(render(file))
	expect.reference_screenshot(child.get_screenshot())
end

T["throws"] = MiniTest.new_set({
	parametrize = {
		{ "block/numbers.lua" },
		{ "mixed/nested_numbers.lua" },
	},
})

T["throws"]["error"] = function(file)
	local pattern = "Inline flow must contain only inline children"
	expect.error(child.lua, pattern, render(file))
end

return T
