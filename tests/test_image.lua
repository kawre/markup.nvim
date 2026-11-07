---@module 'mini.test'

local new_set = MiniTest.new_set
local eq = MiniTest.expect.equality
local child = MiniTest.new_child_neovim()

local T = new_set({
	hooks = {
		pre_case = function()
			child.restart({ "-u", "scripts/minimal_init.lua" })
			child.o.lines, child.o.columns = 20, 60
			child.lua([[
				m = require("markup")
				reactive = require("markup.reactive")
				images = require("markup.image")

				-- Records what would reach the terminal.
				shown, deleted, next_id = {}, {}, 0
				images.backend = {
					set = function(data_or_id, opts)
						if type(data_or_id) == "number" then
							shown[data_or_id] = vim.deepcopy(opts)
							return data_or_id
						end
						next_id = next_id + 1
						shown[next_id] = vim.deepcopy(opts)
						return next_id
					end,
					del = function(id)
						deleted[#deleted + 1] = id
						shown[id] = nil
						return true
					end,
				}

				--- A PNG header for an image of the given pixels.
				function png(width, height)
					local function u32(n)
						return string.char(math.floor(n / 16777216) % 256, math.floor(n / 65536) % 256, math.floor(n / 256) % 256, n % 256)
					end
					return "\137PNG\r\n\26\n" .. u32(13) .. "IHDR" .. u32(width) .. u32(height) .. "rest"
				end

				win = Markup.window({ position = "current", hijack = true, show = false, minimal = true })
				win.buf = vim.api.nvim_get_current_buf()
				win:show()
				view = Markup.view(win)

				function count()
					return vim.tbl_count(shown)
				end
				function only()
					local _, opts = next(shown)
					return opts
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
	child.lua("reactive.flush(); reactive.flush()")
end

local function get(code)
	return child.lua_get(code)
end

T["size"] = new_set()

T["size"]["reads a png header"] = function()
	eq(get("{ images.png_size(png(200, 100)) }"), { 200, 100 })
	eq(get("images.png_size('not a png')"), vim.NIL)
end

T["size"]["follows the proportions of the image"] = function()
	-- Cells are twice as tall as wide, so 200 by 100 pixels is 20 by 5 cells.
	eq(get("{ images.size(png(200, 100), 20) }"), { 20, 5 })
	eq(get("{ images.size(png(200, 100), 20, 8) }"), { 20, 8 })
end

T["takes its size in the layout"] = function()
	run([[view:render(m.block({ m.block("above"), m.image({ data = png(200, 100), width = 20 }), m.block("below") }))]])
	local lines = get("vim.api.nvim_buf_get_lines(0, 0, -1, false)")
	eq(lines[1], "above")
	eq(lines[7], "below")
end

T["is drawn over its box"] = function()
	run([[view:render(m.block({ m.block("above"), m.block({ padding_left = 3, m.image({ data = png(200, 100), width = 20 }) }) }))]])
	eq(get("count()"), 1)
	local top = get("vim.fn.getwininfo(win.win)[1].winrow")
	local left = get("vim.fn.getwininfo(win.win)[1].wincol")
	eq(get("only()"), { row = top + 1, col = left + 3, width = 20, height = 5 })
end

T["moves with its box"] = function()
	run([[
		above = m.signal(1)
		view:render(m.block({
			function() local rows = {} for i = 1, above() do rows[i] = m.block("x") end return rows end,
			m.image({ data = png(100, 100), width = 10 }),
		}))
	]])
	local first = get("only().row")
	run("above(3)")
	eq(get("only().row"), first + 2)
	-- Moved rather than sent again.
	eq(get("next_id"), 1)
end

T["closing what holds it takes it away"] = function()
	run([[
		open = m.signal(true)
		view:render(m.block({ m.show(open, function() return m.image({ data = png(100, 100), width = 10 }) end) }))
	]])
	eq(get("count()"), 1)

	run("open(false)")
	eq(get("count()"), 0)

	run("open(true)")
	eq(get("count()"), 1)
end

T["a collapse hides it while it is cut"] = function()
	run([[
		Markup.animate.manual = true
		open = m.signal(true)
		view:render(m.block({ m.collapse(open, function() return m.image({ data = png(100, 100), width = 10 }) end, { duration = 100 }) }))
	]])
	eq(get("count()"), 1)

	-- Partway closed, the box is cut, and an image cannot be.
	run("open(false)")
	run("Markup.animate.tick(30)")
	eq(get("count()"), 0)

	run("open(true)")
	run("Markup.animate.tick(500)")
	eq(get("count()"), 1)
end

T["scrolling it out of sight takes it away"] = function()
	run([[
		local rows = { m.image({ data = png(100, 100), width = 10 }) }
		for i = 1, 60 do rows[#rows + 1] = m.block("row " .. i) end
		view:render(m.block(rows))
	]])
	eq(get("count()"), 1)

	run([[
		vim.api.nvim_win_set_cursor(0, { 40, 0 })
		vim.cmd("normal! zt")
		view:place_images()
	]])
	eq(get("count()"), 0)

	run([[
		vim.cmd("normal! gg")
		view:place_images()
	]])
	eq(get("count()"), 1)
end

T["leaves with its window and its view"] = function()
	run([[view:render(m.image({ data = png(100, 100), width = 10 }))]])
	eq(get("count()"), 1)
	run("view:destroy()")
	eq(get("count()"), 0)
end

T["waits for its data"] = function()
	run([[
		data = m.signal(nil)
		view:render(m.image({ data = data, width = 10 }))
	]])
	eq(get("count()"), 0)
	run("data(png(100, 100))")
	eq(get("count()"), 1)
end

T["says what is there without a backend"] = function()
	run([[
		images.backend = nil
		view:render(m.image({ data = png(100, 100), width = 20, alt = "a diagram" }))
	]])
	eq(get("vim.trim(vim.api.nvim_buf_get_lines(0, 0, 1, false)[1])"), "a diagram")
end

return T
