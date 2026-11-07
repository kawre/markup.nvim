---@module 'mini.test'

local new_set = MiniTest.new_set
local eq = MiniTest.expect.equality
local child = MiniTest.new_child_neovim()

local T = new_set({
	hooks = {
		pre_case = function()
			child.restart({ "-u", "scripts/minimal_init.lua" })
			child.lua([[
				require("markup")
				notes = {}
				vim.notify = function(msg, lvl) notes[#notes + 1] = { msg = msg, lvl = lvl } end
			]])
		end,
		post_once = function()
			child.stop()
		end,
	},
})

T["calling it tells the user, at the info level"] = function()
	child.lua([[Markup.log("hello", "there")]])
	eq(child.lua_get("notes"), { { msg = "hello there", lvl = vim.log.levels.INFO } })
end

T["debug stays quiet unless debugging"] = function()
	child.lua([[
		Markup.config.debug = false
		Markup.log.debug("hidden")
		Markup.config.debug = true
		Markup.log.debug("shown")
	]])
	eq(child.lua_get("#notes"), 1)
	eq(child.lua_get("notes[1].msg"), "shown")
end

return T
