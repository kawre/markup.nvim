---@module 'mini.test'
---@module 'markup'

local helpers = dofile("tests/helpers.lua")
local markup = require("markup")
local new_set = MiniTest.new_set
local expect, eq = MiniTest.expect, MiniTest.expect.equality
local child = MiniTest.new_child_neovim()

local T = new_set({
	hooks = {
		pre_once = function()
			-- child.restart({ "-u", "scripts/minimal_init.lua" })
			markup = helpers.mock_markup()
			child.start({ "-u", "scripts/minimal_init.lua" })
			child.lua([[markup = require('markup')]])
		end,
		pre_case = function()
			child.o.lines, child.o.columns = 15, 60
		end,
		post_once = function()
			child.stop()
			markup = require("markup")
		end,
	},
})

return T
