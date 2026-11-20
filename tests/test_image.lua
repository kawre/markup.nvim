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
	run(
		[[view:render(m.block({ m.block("above"), m.image({ data = png(200, 100), width = 20 }), m.block("below") }))]]
	)
	local lines = get("vim.api.nvim_buf_get_lines(0, 0, -1, false)")
	eq(lines[1], "above")
	eq(lines[7], "below")
end

T["is drawn over its box"] = function()
	run(
		[[view:render(m.block({ m.block("above"), m.block({ padding_left = 3, m.image({ data = png(200, 100), width = 20 }) }) }))]]
	)
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

T["a width can follow a signal"] = function()
	run([[
		room = m.signal(20)
		view:render(m.image({ data = png(200, 100), width = room }))
	]])
	eq(get("only().width"), 20)
	run("room(10)")
	eq(get("{ only().width, only().height }"), { 10, 3 })
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
		images.resolve = function() return nil end
		view:render(m.image({ data = png(100, 100), width = 20, alt = "a diagram" }))
	]])
	eq(get("vim.trim(vim.api.nvim_buf_get_lines(0, 0, 1, false)[1])"), "a diagram")
end

T["backends"] = new_set()

T["backends"]["one that is set wins"] = function()
	eq(get("images.resolve() == images.backend"), true)
end

T["backends"]["vim.ui.img comes first"] = function()
	run([[
		images.backend = nil
		native = { set = function() end, del = function() end }
		images.native = function() return native end
	]])
	eq(get("images.resolve() == native"), true)
end

local function fake_image_nvim()
	run([[
		images.backend = nil
		images.native = function() return nil end
		calls = {}
		package.loaded["image"] = {
			from_file = function(path, opts)
				local image = { path = path, opts = opts }
				function image:render(geometry) calls[#calls + 1] = { "render", self.path, geometry } end
				function image:clear() calls[#calls + 1] = { "clear", self.path } end
				return image
			end,
		}
	]])
end

T["backends"]["image.nvim when Neovim cannot"] = function()
	fake_image_nvim()
	eq(get("images.resolve() ~= nil"), true)
	eq(get("images.available()"), true)
end

T["backends"]["image.nvim gets a file and cells from zero"] = function()
	fake_image_nvim()
	run([[
		backend = images.resolve()
		id = backend.set(png(100, 100), { row = 3, col = 5, width = 10, height = 5 })
	]])
	eq(get("calls[1][1]"), "render")
	eq(get("calls[1][3]"), { x = 4, y = 2, width = 10, height = 5 })
	eq(get("vim.fn.readblob(calls[1][2]) == png(100, 100)"), true)

	run([[backend.set(id, { row = 6, col = 5, width = 10, height = 5 })]])
	eq(get("calls[2][3].y"), 5)

	run([[deleted_it = backend.del(id)]])
	eq(get("calls[3][1]"), "clear")
	eq(get("deleted_it"), true)
end

T["backends"]["image.nvim draws what a view shows"] = function()
	fake_image_nvim()
	run([[view:render(m.image({ data = png(100, 100), width = 10 }))]])
	eq(get("calls[1] and calls[1][1]"), "render")
end

T["backends"]["nothing without either"] = function()
	run([[
		images.backend = nil
		images.native = function() return nil end
		package.loaded["image"] = nil
		package.preload["image"] = function() error("not installed") end
	]])
	eq(get("images.available()"), false)
end

T["covered"] = new_set()

T["covered"]["a popup over an image takes it away until it closes"] = function()
	run([[view:render(m.block({ m.image({ data = png(200, 100), width = 20 }) }))]])
	eq(get("count()"), 1)

	run([[
		popup = vim.api.nvim_open_win(vim.api.nvim_create_buf(false, true), false, {
			relative = "editor", row = 2, col = 5, width = 10, height = 3, border = "rounded",
		})
		view:place_images()
	]])
	eq(get("count()"), 0)

	run([[
		vim.api.nvim_win_close(popup, true)
		view:place_images()
	]])
	eq(get("count()"), 1)
end

T["covered"]["a popup elsewhere leaves it be"] = function()
	run([[view:render(m.block({ m.image({ data = png(200, 100), width = 20 }) }))]])
	run([[
		popup = vim.api.nvim_open_win(vim.api.nvim_create_buf(false, true), false, {
			relative = "editor", row = 15, col = 40, width = 10, height = 2,
		})
		view:place_images()
	]])
	eq(get("count()"), 1)
end

T["covered"]["a float under the image's own float does not cover it"] = function()
	run([[
		below = vim.api.nvim_open_win(vim.api.nvim_create_buf(false, true), false, {
			relative = "editor", row = 0, col = 0, width = 60, height = 18, zindex = 10,
		})
		float = Markup.window({ position = "float", row = 0, col = 0, width = 50, height = 15, zindex = 40, dim = false, enter = true })
		float_view = Markup.view(float)
		float_view:render(m.block({ m.image({ data = png(200, 100), width = 20 }) }))
		reactive.flush(); reactive.flush()
		float_view:place_images()
	]])
	eq(get("count()"), 1)
end

T["frames"] = new_set()

T["frames"]["play in a loop, each for its delay"] = function()
	run([[
		Markup.animate.manual = true
		Markup.animate.enabled = true
		local function frame(n) return png(200, 100) .. "frame" .. n end
		gif = { { data = frame(1), delay = 100 }, { data = frame(2), delay = 50 }, { data = frame(3), delay = 100 } }
		uploaded = {}
		local set = images.backend.set
		images.backend.set = function(data_or_id, opts)
			if type(data_or_id) == "string" then uploaded[#uploaded + 1] = data_or_id:match("frame%d") end
			return set(data_or_id, opts)
		end
		shown_flag = m.signal(true)
		view:render(m.block({ m.show(shown_flag, function() return m.image({ data = gif, width = 20 }) end) }))
	]])
	local function tick(ms)
		run(("Markup.animate.tick(%d)"):format(ms))
		return get("uploaded[#uploaded]")
	end
	eq(get("uploaded[#uploaded]"), "frame1")
	eq(tick(60), "frame1")
	eq(tick(60), "frame2")
	eq(tick(60), "frame3")
	-- 250 ms in all, so it starts over.
	eq(tick(100), "frame1")
	eq(get("count()"), 1)

	run("shown_flag(false)")
	eq(get("count()"), 0)
	eq(get("Markup.animate.count()"), 0)
end

T["frames"]["a single frame is a still image"] = function()
	run(
		[[view:render(m.block({ m.image({ data = { { data = png(200, 100), delay = 100 } }, width = 20 }) }))]]
	)
	eq(get("count()"), 1)
	eq(get("Markup.animate.count()"), 0)
end

return T
