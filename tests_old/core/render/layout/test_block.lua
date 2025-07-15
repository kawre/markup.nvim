---@module 'mini.test'

local helpers = dofile("tests/helpers/init.lua")
local expect = MiniTest.expect
local child = MiniTest.new_child_neovim()

local path = "tests/core/render/layout/assets/"
local render = helpers.mock_layout(path, "Block")

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
		{ "block/numbers.lua" },
		{ "mixed/nested_numbers.lua" },
		{ "mixed/numbers.lua" },
		{ "empty.lua" },
		{ "nothing.lua" },
	},
})

T["render()"]["works"] = function(file)
	child.lua(render(file))
	expect.reference_screenshot(child.get_screenshot())
end

return T
