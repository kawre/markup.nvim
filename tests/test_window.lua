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

T["close"] = new_set()

T["close"]["a view that keeps changing while closed shows where it got to"] = function()
	child.lua([[
		m = require("markup")
		reactive = require("markup.reactive")
		errors = {}
		vim.notify = function(msg, level)
			if level == vim.log.levels.ERROR then errors[#errors + 1] = tostring(msg) end
		end
		win = Markup.window({ position = "bottom", height = 5 })
		view = Markup.view(win)
		state = m.signal("queued")
		view:render(m.block(function() return "judge: " .. state() end))
		reactive.flush()
		before = vim.api.nvim_buf_get_lines(win.buf, 0, 1, false)[1]

		-- As the judge goes on after the console is closed.
		win:close()
		state("judging")
		reactive.flush()
		state("done")
		reactive.flush()
		vim.wait(50, function() return false end, 5)

		win:show()
		reactive.flush()
		vim.wait(50, function() return false end, 5)
		after = vim.api.nvim_buf_get_lines(win.buf, 0, 1, false)[1]
	]])
	eq(child.lua_get("errors"), {})
	eq(child.lua_get("before"), "judge: queued")
	eq(child.lua_get("after"), "judge: done")
end

T["dim"] = new_set()

T["dim"]["dims the windows under it on a transparent background"] = function()
	child.lua([[
		vim.api.nvim_set_hl(0, "Normal", { fg = "#cdd6f4" })
		vim.cmd("doautocmd ColorScheme")
		editor = vim.api.nvim_get_current_win()
		popup = Markup.window({ width = 0.5, height = 0.5, dim = true, enter = true, text = { "hi" } })
		local ns = vim.api.nvim_get_hl_ns({ winid = editor })
		dimmed_fg = ns > 0 and vim.api.nvim_get_hl(ns, { name = "Normal" }).fg or false
	]])
	-- No float to blend with a background that is not there.
	eq(child.lua_get("backdrop()"), vim.NIL)
	-- The text under it at 60% of its brightness.
	eq(
		child.lua_get("dimmed_fg"),
		child.lua_get(
			"math.floor(0xcd * 0.6) * 65536 + math.floor(0xd6 * 0.6) * 256 + math.floor(0xf4 * 0.6)"
		)
	)

	child.lua("popup:close()")
	eq(child.lua_get("math.max(vim.api.nvim_get_hl_ns({ winid = editor }), 0)"), 0)
end

T["dim"]["lays a backdrop under the popup"] = function()
	child.lua(
		[[popup = Markup.window({ width = 0.5, height = 0.5, dim = true, enter = true, text = { "hi" } })]]
	)
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
		own_ns = vim.api.nvim_get_hl_ns({ winid = first.win })
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
	eq(
		child.lua_get("normal.fg"),
		child.lua_get(
			"math.floor(0xcd * 0.6) * 65536 + math.floor(0xd6 * 0.6) * 256 + math.floor(0xf4 * 0.6)"
		)
	)
	-- Its own again, which its `winhighlight` lives in.
	eq(child.lua_get("restored_ns"), child.lua_get("own_ns"))
end

-- Found by tests/test_properties.lua: `winhighlight` lives in a namespace of
-- the window, which dimming replaced and closing then set to 0.
T["dim"]["gives a float its winhighlight back"] = function()
	child.lua([[
		vim.api.nvim_set_hl(0, "Special", { fg = "#ff0000", bg = "#00ff00" })
		float = vim.api.nvim_open_win(vim.api.nvim_create_buf(false, true), false, {
			relative = "editor", row = 1, col = 1, width = 10, height = 3, zindex = 40,
		})
		vim.wo[float].winhighlight = "Normal:Special"
		own = vim.api.nvim_get_hl_ns({ winid = float })
		popup = Markup.window({ width = 0.5, height = 0.5, dim = true, enter = true })
		popup:close()
		after = vim.api.nvim_get_hl_ns({ winid = float })
		normal = after > 0 and vim.api.nvim_get_hl(after, { name = "Normal" }) or nil
	]])
	if child.lua_get("own") > 0 then
		eq(child.lua_get("after"), child.lua_get("own"))
		eq(child.lua_get("normal"), { link = "Special" })
	else
		-- Before Neovim 0.12 `winhighlight` is not a namespace of the window,
		-- so it has none to give back, and the option is still there.
		eq(child.lua_get("after") <= 0, true)
		eq(child.lua_get("vim.wo[float].winhighlight"), "Normal:Special")
	end
end

T["dim"]["dims a float in the colors its winhighlight gives it"] = function()
	child.lua([[
		vim.api.nvim_set_hl(0, "Special", { fg = "#ff0000", bg = "#00ff00" })
		float = vim.api.nvim_open_win(vim.api.nvim_create_buf(false, true), false, {
			relative = "editor", row = 1, col = 1, width = 10, height = 3, zindex = 40,
		})
		vim.wo[float].winhighlight = "Normal:Special"
		popup = Markup.window({ width = 0.5, height = 0.5, dim = 0.5, enter = true })
		normal = vim.api.nvim_get_hl(vim.api.nvim_get_hl_ns({ winid = float }), { name = "Normal", link = false })
	]])
	-- Half as bright as Special, not as Normal.
	eq(child.lua_get("normal.fg"), 0x7f0000)
	eq(child.lua_get("normal.bg"), 0x007f00)
end

T["dim"]["keeps a float dimmed while a popup over it is still open"] = function()
	child.lua([[
		float = vim.api.nvim_open_win(vim.api.nvim_create_buf(false, true), false, {
			relative = "editor", row = 1, col = 1, width = 10, height = 3, zindex = 40,
		})
		outer = Markup.window({ width = 0.6, height = 0.6, dim = true, enter = true })
		dimmed = vim.api.nvim_get_hl_ns({ winid = float })
		inner = Markup.window({ width = 0.3, height = 0.3, dim = true, enter = true })
		inner:close()
		after_inner = vim.api.nvim_get_hl_ns({ winid = float })
		outer:close()
		after_outer = vim.api.nvim_get_hl_ns({ winid = float })
	]])
	eq(child.lua_get("dimmed ~= 0"), true)
	eq(child.lua_get("after_inner == dimmed"), true)
	eq(child.lua_get("after_outer"), 0)
end

T["dim"]["closing the outer popup first leaves the inner one dimming"] = function()
	child.lua([[
		float = vim.api.nvim_open_win(vim.api.nvim_create_buf(false, true), false, {
			relative = "editor", row = 1, col = 1, width = 10, height = 3, zindex = 40,
		})
		outer = Markup.window({ width = 0.6, height = 0.6, dim = true, enter = true })
		inner = Markup.window({ width = 0.3, height = 0.3, dim = true, enter = true })
		dimmed = vim.api.nvim_get_hl_ns({ winid = float })
		outer:close()
		after_outer = vim.api.nvim_get_hl_ns({ winid = float })
		inner:close()
		after_inner = vim.api.nvim_get_hl_ns({ winid = float })
	]])
	eq(child.lua_get("after_outer == dimmed"), true)
	eq(child.lua_get("after_inner"), 0)
end

return T
