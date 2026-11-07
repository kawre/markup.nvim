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
				m = require("markup")
				reactive = require("markup.reactive")
				picked = nil
				function open(extra)
					local items = {}
					for i, name in ipairs({ "Two Sum", "Add Two Numbers", "Three Sum", "Reverse Integer" }) do
						items[i] = {
							label = name,
							keywords = tostring(i),
							prefix = { { i .. ". ", "Comment" } },
							suffix = { { "50%", "Comment" } },
							value = i,
						}
					end
					picker = Markup.picker(vim.tbl_extend("force", {
						title = "Pick",
						items = items,
						on_select = function(value) picked = value end,
					}, extra or {}))
					reactive.flush()
				end
				function list_lines()
					for _, win in ipairs(vim.api.nvim_list_wins()) do
						local buf = vim.api.nvim_win_get_buf(win)
						if win ~= vim.api.nvim_get_current_win() and vim.api.nvim_win_get_config(win).relative ~= "" then
							return vim.tbl_map(function(line)
								return (line:gsub("%s+$", ""))
							end, vim.api.nvim_buf_get_lines(buf, 0, -1, false))
						end
					end
				end
				function floats()
					return #vim.tbl_filter(function(win)
						return vim.api.nvim_win_get_config(win).relative ~= ""
					end, vim.api.nvim_list_wins())
				end
			]])
		end,
		post_once = function()
			child.stop()
		end,
	},
})

local function type(keys)
	child.type_keys(keys)
	child.lua("reactive.flush()")
end

T["opens a prompt over a list"] = function()
	child.lua("open()")
	eq(child.lua_get("floats()"), 2)
	eq(child.fn.mode(), "i")
	eq(#child.lua_get("list_lines()"), 4)
end

T["the list sits right below the prompt"] = function()
	child.lua([[
		open()
		prompt = vim.api.nvim_get_current_win()
		for _, win in ipairs(vim.api.nvim_list_wins()) do
			if win ~= prompt and vim.api.nvim_win_get_config(win).relative ~= "" then list = win end
		end
	]])
	-- One panel: the prompt, then the line between them.
	eq(child.lua_get("vim.fn.win_screenpos(list)[1] - vim.fn.win_screenpos(prompt)[1]"), 2)
	eq(child.lua_get("vim.api.nvim_win_get_config(list).border[1]"), "├")
	eq(child.lua_get("vim.fn.win_screenpos(list)[2] == vim.fn.win_screenpos(prompt)[2]"), true)
end

T["filters as you type"] = function()
	child.lua("open()")
	type("sum")
	local lines = child.lua_get("list_lines()")
	eq(#lines, 2)
	eq(lines[1]:find("Sum", 1, true) ~= nil, true)
end

T["matches hidden keywords"] = function()
	child.lua("open()")
	type("4")
	local lines = child.lua_get("list_lines()")
	eq(#lines, 1)
	eq(lines[1]:find("Reverse Integer", 1, true) ~= nil, true)
end

T["highlights what matched"] = function()
	child.lua("open()")
	type("tw")
	child.lua([[
		matched = {}
		for _, view in pairs(vim.tbl_keys(Markup.views)) do
			local buf = view.win.buf
			if buf and vim.api.nvim_buf_is_valid(buf) then
				for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(buf, view.ns, 0, -1, { details = true })) do
					if mark[4].hl_group == "MarkupPickerMatch" then
						matched[#matched + 1] = vim.api.nvim_buf_get_text(buf, mark[2], mark[3], mark[2], mark[4].end_col, {})[1]
					end
				end
			end
		end
	]])
	eq(child.lua_get("table.concat(matched)"):lower():find("tw", 1, true) ~= nil, true)
end

T["shows a count"] = function()
	child.lua("open()")
	type("sum")
	child.lua([[
		local marks = vim.api.nvim_buf_get_extmarks(0, -1, 0, -1, { details = true })
		texts = {}
		for _, mark in ipairs(marks) do
			for _, chunk in ipairs(mark[4].virt_text or {}) do texts[#texts + 1] = chunk[1] end
		end
	]])
	eq(vim.tbl_contains(child.lua_get("texts"), "2/4"), true)
end

T["moves and picks"] = function()
	child.lua("open()")
	type("<C-n><C-n>")
	type("<CR>")
	eq(child.lua_get("picked"), 3)
	eq(child.lua_get("floats()"), 0)
	eq(child.fn.mode(), "n")
end

T["stays inside the list"] = function()
	child.lua("open()")
	type("<C-p><C-p>")
	type("<CR>")
	eq(child.lua_get("picked"), 1)
end

T["picks the best match"] = function()
	child.lua("open()")
	type("reverse<CR>")
	eq(child.lua_get("picked"), 4)
end

T["moving right after typing uses the new query"] = function()
	child.lua("open()")
	type("sum<C-n><CR>")
	eq(child.lua_get("picked"), 3)
end

T["closes without picking"] = function()
	child.lua("open()")
	type("<Esc>")
	eq(child.lua_get("floats()"), 0)
	eq(child.lua_get("picked"), vim.NIL)
end

T["closes when focus leaves"] = function()
	child.lua([[
		origin = vim.api.nvim_get_current_win()
		open()
		vim.api.nvim_set_current_win(origin)
	]])
	child.lua("vim.wait(20, function() return false end)")
	eq(child.lua_get("floats()"), 0)
end

T["says when nothing matches"] = function()
	child.lua("open()")
	type("zzzz")
	eq(child.lua_get("list_lines()")[1]:find("No matches", 1, true) ~= nil, true)
	type("<CR>")
	eq(child.lua_get("picked"), vim.NIL)
end

T["scrolls to keep the selection in view"] = function()
	child.lua([[
		local many = {}
		for i = 1, 50 do many[i] = { label = "item " .. i, value = i } end
		open({ items = many, height = 5 })
	]])
	for _ = 1, 7 do
		type("<C-n>")
	end
	local lines = child.lua_get("list_lines()")
	eq(#lines, 5)
	eq(lines[5]:find("item 8", 1, true) ~= nil, true)
	type("<CR>")
	eq(child.lua_get("picked"), 8)
end

T["returns to the window it came from"] = function()
	child.lua([[
		vim.cmd("vnew")
		origin = vim.api.nvim_get_current_win()
		open()
	]])
	type("<Esc>")
	eq(child.lua_get("vim.api.nvim_get_current_win() == origin"), true)
end

T["handles thousands of items"] = function()
	child.lua([[
		local many = {}
		for i = 1, 5000 do many[i] = { label = "problem number " .. i, keywords = "slug-" .. i, value = i } end
		open({ items = many })
		local started = vim.uv.hrtime()
		vim.api.nvim_buf_set_lines(0, 0, -1, false, { "number 4999" })
		vim.api.nvim_exec_autocmds("TextChangedI", { buffer = 0 })
		elapsed = (vim.uv.hrtime() - started) / 1e6
	]])
	eq(child.lua_get("elapsed < 200"), true)
	eq(child.lua_get("list_lines()")[1]:find("4999", 1, true) ~= nil, true)
end

T["a label too long is cut before the suffix"] = function()
	child.o.columns = 40
	child.lua([[
		local items = {}
		for i = 1, 3 do
			items[i] = {
				label = "Longest Substring Without Repeating Characters",
				prefix = { { i .. ". " } },
				suffix = { { "58.1%" } },
				value = i,
			}
		end
		Markup.picker({ title = "Pick", items = items, on_select = function() end })
		reactive.flush()
	]])
	for _, line in ipairs(child.lua_get("list_lines()")) do
		if line ~= "" then
			-- The suffix ends the row, and nothing of the label runs past it.
			eq(line:match("58%.1%%$") ~= nil, true)
			eq(select(2, line:gsub("58%.1%%", "")), 1)
			eq(line:find("Characters", 1, true), nil)
		end
	end
end

return T
