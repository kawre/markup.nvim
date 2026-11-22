---@module 'mini.test'

local new_set = MiniTest.new_set
local eq = MiniTest.expect.equality
local child = MiniTest.new_child_neovim()

local T = new_set({
	hooks = {
		pre_case = function()
			child.restart({ "-u", "scripts/minimal_init.lua" })
			child.o.lines, child.o.columns = 30, 80
			child.lua([[
				require("markup")
				-- Lua's filetype plugin starts treesitter, which needs a parser
				-- the tests do not have, and nothing here needs it.
				vim.cmd("filetype plugin off")
				-- A folder of its own, so the playground of whoever runs the tests stays as it is.
				Markup.playground.path = vim.fn.tempname()
				vim.fn.mkdir(Markup.playground.path, "p")
				runs = {}
				--- A playground file that counts its runs and renders `text`, if any.
				function write(name, text)
					local render = text
							and ("Markup.playground.preview:render(require('markup').block(%q))"):format(text)
						or ""
					vim.fn.writefile({
						("runs[%q] = (runs[%q] or 0) + 1"):format(name, name),
						render,
					}, Markup.playground.path .. "/" .. name)
				end
				function preview()
					local buf = Markup.playground.preview.win.buf
					return vim.tbl_map(function(line)
						return (line:gsub("%s+$", ""))
					end, vim.api.nvim_buf_get_lines(buf, 0, -1, false))
				end
				function settle()
					vim.wait(50, function() return false end, 5)
					require("markup.reactive").flush()
				end
			]])
		end,
		post_once = function()
			child.stop()
		end,
	},
})

local function run(code)
	child.lua(code)
	child.lua("settle()")
end

--- Saves the file the tab shows, after replacing what it renders with `text`.
local function save(text)
	run(([[
		vim.api.nvim_buf_set_lines(0, 1, 2, false, {
			("Markup.playground.preview:render(require('markup').block(%%q))"):format(%q),
		})
		vim.cmd("silent write")
	]]):format(text))
end

T["previews the file it opens"] = function()
	run([[
		write("a.lua", "from a")
		Markup.playground.open({ file = "a.lua" })
	]])
	eq(child.lua_get("preview()"), { "from a" })
	eq(child.lua_get("runs"), { ["a.lua"] = 1 })
end

T["switching to another file runs nothing until it is saved"] = function()
	run([[
		write("a.lua", "from a")
		write("b.lua", "from b")
		Markup.playground.open({ file = "a.lua" })
	]])
	-- By name, from the playground the tab is in, as one would type it.
	run([[vim.cmd.edit("b.lua")]])
	eq(child.lua_get("preview()"), { "from a" })
	eq(child.lua_get("runs"), { ["a.lua"] = 1 })
	-- It is the one `run` runs now.
	eq(
		child.lua_get("Markup.playground.file"),
		child.lua_get("vim.fs.normalize(Markup.playground.path .. '/b.lua')")
	)

	save("saved b")
	eq(child.lua_get("preview()"), { "saved b" })
	eq(child.lua_get("runs"), { ["a.lua"] = 1, ["b.lua"] = 1 })
end

T["saving the file the preview shows runs it again"] = function()
	run([[
		write("a.lua", "from a")
		Markup.playground.open({ file = "a.lua" })
	]])
	save("saved a")
	eq(child.lua_get("preview()"), { "saved a" })
	eq(child.lua_get("runs['a.lua']"), 2)
end

T["a saved file that renders nothing leaves nothing of the one before"] = function()
	run([[
		write("a.lua", "from a")
		write("quiet.lua", nil)
		Markup.playground.open({ file = "a.lua" })
		vim.cmd.edit("quiet.lua")
		vim.cmd("silent write")
	]])
	eq(child.lua_get("preview()"), { "" })
	eq(child.lua_get("runs['quiet.lua']"), 1)
end

T["going back to the file runs nothing"] = function()
	run([[
		write("a.lua", "from a")
		Markup.playground.open({ file = "a.lua" })
	]])
	-- Into the preview and back, as when a picker the file opened closes.
	run([[vim.api.nvim_set_current_win(Markup.playground.preview.win.win)]])
	run([[vim.cmd.wincmd("p")]])
	eq(child.lua_get("runs"), { ["a.lua"] = 1 })
end

T["a file outside the playground leaves the preview as it is"] = function()
	run([[
		write("a.lua", "from a")
		Markup.playground.open({ file = "a.lua" })
		other = vim.fn.tempname() .. ".lua"
		vim.fn.writefile({ "error('not run')" }, other)
	]])
	run([[vim.cmd.edit(other)]])
	run([[vim.cmd("silent write")]])
	eq(child.lua_get("preview()"), { "from a" })
	eq(child.lua_get("runs"), { ["a.lua"] = 1 })
end

return T
