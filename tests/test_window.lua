---@module 'mini.test'

local new_set = MiniTest.new_set
local eq = MiniTest.expect.equality
local child = MiniTest.new_child_neovim()

local T = new_set({
	hooks = {
		pre_case = function()
			child.restart({ "-u", "scripts/minimal_init.lua" })
			child.o.lines, child.o.columns = 30, 100
			child.lua([[
				require("markup")
				vim.o.termguicolors = true
				vim.api.nvim_set_hl(0, "Normal", { fg = "#cdd6f4", bg = "#1e1e2e" })
				function floats()
					local list = {}
					for _, win in ipairs(vim.api.nvim_list_wins()) do
						local config = vim.api.nvim_win_get_config(win)
						if config.relative ~= "" then
							list[#list + 1] = { win = win, z = config.zindex, ft = vim.bo[vim.api.nvim_win_get_buf(win)].filetype }
						end
					end
					return list
				end
				function backdrop()
					for _, float in ipairs(floats()) do
						if float.ft == "markup_backdrop" then return float end
					end
				end
			]])
		end,
		post_once = function()
			child.stop()
		end,
	},
})

T["dim"] = new_set()

T["dim"]["lays a backdrop under the popup"] = function()
	child.lua([[popup = Markup.window({ width = 0.5, height = 0.5, dim = true, enter = true, text = { "hi" } })]])
	eq(child.lua_get("backdrop() ~= nil"), true)
	eq(child.lua_get("backdrop().z < vim.api.nvim_win_get_config(popup.win).zindex"), true)
end

T["dim"]["can be turned off"] = function()
	child.lua([[popup = Markup.window({ width = 0.5, height = 0.5, dim = false, enter = true })]])
	eq(child.lua_get("backdrop()"), vim.NIL)
end

T["dim"]["dims the floats already open, and gives their colors back"] = function()
	child.lua([[
		first = Markup.window({ width = 0.8, height = 0.8, dim = false, enter = true, text = { "first" } })
		second = Markup.window({ width = 0.4, height = 0.4, dim = 0.4, enter = true, text = { "second" } })
		first_z = vim.api.nvim_win_get_config(first.win).zindex
		second_z = vim.api.nvim_win_get_config(second.win).zindex
		dimmed_ns = vim.api.nvim_get_hl_ns({ winid = first.win })
		normal = vim.api.nvim_get_hl(dimmed_ns, { name = "Normal" })
		second.win_was = second.win
		second:close()
		restored_ns = vim.api.nvim_get_hl_ns({ winid = first.win })
	]])
	-- Above the first, and the backdrop not over it, which would hide it.
	eq(child.lua_get("second_z > first_z"), true)
	eq(child.lua_get("dimmed_ns ~= 0"), true)
	-- 0.4 dark leaves 60% of each color.
	eq(child.lua_get("normal.fg"), child.lua_get("math.floor(0xcd * 0.6) * 65536 + math.floor(0xd6 * 0.6) * 256 + math.floor(0xf4 * 0.6)"))
	eq(child.lua_get("restored_ns"), 0)
end

return T
