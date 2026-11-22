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
				win = Markup.window({ position = "current", hijack = true, show = false, minimal = false })
				win.buf = vim.api.nvim_get_current_buf()
				win:show()
				view = Markup.view(win)
				function lines()
					local result = vim.api.nvim_buf_get_lines(win.buf, 0, -1, false)
					return vim.tbl_map(function(line)
						return (line:gsub("%s+$", ""))
					end, result)
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
end

local function lines()
	return child.lua_get("lines()")
end

local function marks()
	return child.lua_get([[vim.tbl_map(function(mark)
		return { mark[2], mark[3], mark[4].end_col, mark[4].hl_group }
	end, view:highlights())]])
end

T["drawing"] = new_set()

T["drawing"]["sets cells, text, fills, lines and rects"] = function()
	run([[
		view:render(m.canvas({
			width = 10,
			height = 5,
			draw = function(ctx)
				ctx:rect(0, 0, 10, 5, "single", "Comment")
				ctx:fill(1, 1, 8, 3, ".", "NonText")
				ctx:text(2, 2, "hi!", "Title")
				ctx:set(8, 3, "X", "DiagnosticError")
			end,
		}))
	]])
	eq(lines(), {
		"┌────────┐",
		"│........│",
		"│.hi!....│",
		"│.......X│",
		"└────────┘",
	})
	-- Adjacent cells with the same highlight merge into a single mark.
	eq(marks(), {
		{ 0, 0, 30, "Comment" },
		{ 1, 0, 3, "Comment" },
		{ 1, 3, 11, "NonText" },
		{ 1, 11, 14, "Comment" },
		{ 2, 0, 3, "Comment" },
		{ 2, 3, 4, "NonText" },
		{ 2, 4, 7, "Title" },
		{ 2, 7, 11, "NonText" },
		{ 2, 11, 14, "Comment" },
		{ 3, 0, 3, "Comment" },
		{ 3, 3, 10, "NonText" },
		{ 3, 10, 11, "DiagnosticError" },
		{ 3, 11, 14, "Comment" },
		{ 4, 0, 30, "Comment" },
	})
end

T["drawing"]["draws diagonal lines and clips out-of-bounds writes"] = function()
	run([[
		view:render(m.canvas({
			width = 4,
			height = 4,
			draw = function(ctx)
				ctx:line(0, 0, 3, 3, "*", "Function")
				ctx:set(-1, 0, "!", "Error")
				ctx:set(4, 0, "!", "Error")
				ctx:set(0, -1, "!", "Error")
				ctx:set(0, 4, "!", "Error")
				ctx:text(-2, 1, "abcde", "String")
			end,
		}))
	]])
	eq(lines(), {
		"*",
		"cde",
		"  *",
		"   *",
	})
end

T["drawing"]["handles newlines, tabs and style-only cell updates"] = function()
	run([[
		view:render(m.canvas({
			width = 10,
			height = 3,
			draw = function(ctx)
				ctx:text(0, 0, "a\tb\ncd", "String")
				ctx:set(0, 1, nil, "Title")
			end,
		}))
	]])
	eq(lines(), {
		"a    b",
		"cd",
		"",
	})
	eq(marks(), {
		{ 0, 0, 6, "String" },
		{ 1, 0, 1, "Title" },
		{ 1, 1, 2, "String" },
	})
end

T["drawing"]["handles wide characters, edge clipping and overwriting halves"] = function()
	run([[
		view:render(m.canvas({
			width = 5,
			height = 3,
			draw = function(ctx)
				-- Overwriting right half of '你' replaces its left half with a blank.
				ctx:text(0, 0, "你好", "String")
				ctx:set(1, 0, "X", "Title")
				-- Wide character on the right edge cannot be halved.
				ctx:text(4, 1, "界", "Comment")
				-- Wide character straddling the left edge leaves a blank at 0.
				ctx:text(-1, 2, "世界", "Function")
			end,
		}))
	]])
	eq(lines(), {
		" X好",
		"",
		" 界",
	})
	eq(marks(), {
		{ 0, 0, 1, "String" },
		{ 0, 1, 2, "Title" },
		{ 0, 2, 5, "String" },
		{ 1, 4, 5, "Comment" },
		{ 2, 0, 4, "Function" },
	})
end

T["reactivity"] = new_set()

T["reactivity"]["redraws on signal changes with zero layouts"] = function()
	run([[
		frame = m.signal(1)
		view:render(m.block({
			m.block("header"),
			m.canvas({
				width = 6,
				height = 2,
				draw = function(ctx)
					ctx:text(0, 0, "f=" .. frame(), "Number")
					ctx:set(frame() % 6, 1, "#", "Special")
				end,
			}),
			m.block("footer"),
		}))
		initial_layouts = view.stats.layouts
		frame(2)
		reactive.flush()
		second_layouts = view.stats.layouts
		frame(3)
		reactive.flush()
		third_layouts = view.stats.layouts
	]])
	eq(child.lua_get("initial_layouts > 0"), true)
	eq(child.lua_get("second_layouts"), 0)
	eq(child.lua_get("third_layouts"), 0)
	eq(lines(), {
		"header",
		"f=3",
		"   #",
		"footer",
	})
end

T["reactivity"]["retain keeps previous cells across redraws"] = function()
	run([[
		step = m.signal(0)
		view:render(m.canvas({
			width = 4,
			height = 1,
			retain = true,
			draw = function(ctx)
				ctx:set(step(), 0, tostring(step()), "Number")
			end,
		}))
		step(1)
		reactive.flush()
		step(2)
		reactive.flush()
	]])
	eq(lines(), { "012" })
end

T["layout"] = new_set()

T["layout"]["composes with border, padding, flex siblings and interaction"] = function()
	run([[
		pressed = false
		view:render(m.flex({
			gap = 1,
			m.block({ width = 4, "left" }),
			m.canvas({
				width = 4,
				height = 2,
				border = "single",
				padding = { 0, 1 },
				on_press = function() pressed = true end,
				draw = function(ctx)
					ctx:text(0, 0, "abcd", "Title")
					ctx:text(0, 1, "1234", "String")
				end,
			}),
			m.block("right"),
		}))
		vim.api.nvim_win_set_cursor(win.win, { 2, 7 })
		did_press = view:press()
	]])
	eq(lines(), {
		"left ┌──────┐ right",
		"     │ abcd │",
		"     │ 1234 │",
		"     └──────┘",
	})
	eq(child.lua_get("did_press"), true)
	eq(child.lua_get("pressed"), true)
end

T["layout"]["auto width tracks container size and cleans up on unmount"] = function()
	run([[
		box_width = m.signal(8)
		shown = m.signal(true)
		view:render(m.show(shown, function()
			return m.block({
				width = box_width,
				m.canvas({
					height = 1,
					draw = function(ctx)
						ctx:fill(0, 0, ctx.width, 1, "=", "Comment")
						ctx:text(0, 0, tostring(ctx.width), "Title")
					end,
				}),
			})
		end))
		first = lines()
		listeners_mounted = #view.commit_listeners

		box_width(12)
		reactive.flush()
		resized = lines()

		shown(false)
		reactive.flush()
		listeners_unmounted = #view.commit_listeners
	]])
	eq(child.lua_get("first"), { "8=======" })
	eq(child.lua_get("resized"), { "12==========" })
	eq(child.lua_get("listeners_mounted"), 1)
	eq(child.lua_get("listeners_unmounted"), 0)
end

T["layout"]["reactive dimensions resize the canvas cleanly"] = function()
	run([[
		rows = m.signal(2)
		view:render(m.canvas({
			width = 4,
			height = rows,
			draw = function(ctx)
				for y = 0, ctx.height - 1 do
					ctx:text(0, y, "r" .. y, "String")
				end
			end,
		}))
		before = lines()
		rows(4)
		reactive.flush()
		after = lines()
		rows(0)
		reactive.flush()
		empty = lines()
	]])
	eq(child.lua_get("before"), { "r0", "r1" })
	eq(child.lua_get("after"), { "r0", "r1", "r2", "r3" })
	eq(child.lua_get("empty"), { "" })
end

T["layout"]["negative z canvas paints behind flow without blocking presses"] = function()
	run([[
		pressed = false
		view:render(m.block({
			m.canvas({
				position = "absolute",
				top = 0,
				left = 0,
				z = -1,
				inert = true,
				width = 10,
				height = 3,
				draw = function(ctx)
					ctx:fill(0, 0, 10, 3, ".", "Comment")
				end,
			}),
			m.block({
				margin_top = 1,
				margin_left = 2,
				width = 4,
				style = "CursorLine",
				on_press = function() pressed = true end,
				"ok",
			}),
		}))
		vim.api.nvim_win_set_cursor(win.win, { 2, 2 })
		did_press = view:press()
	]])
	eq(lines(), {
		"..........",
		"..ok  ....",
		"..........",
	})
	eq(child.lua_get("did_press"), true)
	eq(child.lua_get("pressed"), true)
end

T["layout"]["negative z canvas takes presses where flow has nothing interactive"] = function()
	run([[
		pressed = nil
		view:render(m.block({
			m.canvas({
				position = "absolute",
				top = 0,
				left = 0,
				z = -1,
				width = 10,
				height = 2,
				on_press = function() pressed = "canvas" end,
				draw = function(ctx)
					ctx:fill(0, 0, 10, 2, ".", "Comment")
				end,
			}),
			m.block({ width = 4, on_press = function() pressed = "card" end, "card" }),
			"plain",
		}))
		-- Beside the card, only text that takes no presses is in flow.
		vim.api.nvim_win_set_cursor(win.win, { 2, 2 })
		view:press()
		over_text = pressed
		vim.api.nvim_win_set_cursor(win.win, { 1, 7 })
		view:press()
		beside_card = pressed
		vim.api.nvim_win_set_cursor(win.win, { 1, 1 })
		view:press()
		on_card = pressed
	]])
	eq(child.lua_get("over_text"), "canvas")
	eq(child.lua_get("beside_card"), "canvas")
	eq(child.lua_get("on_card"), "card")
end

T["layout"]["inert flow keeps presses from a negative z canvas"] = function()
	run([[
		pressed = false
		view:render(m.block({
			inert = true,
			m.canvas({
				position = "absolute",
				top = 0,
				left = 0,
				z = -1,
				width = 6,
				height = 1,
				on_press = function() pressed = true end,
				draw = function(ctx)
					ctx:fill(0, 0, 6, 1, ".")
				end,
			}),
			"x",
		}))
		vim.api.nvim_win_set_cursor(win.win, { 1, 3 })
		did_press = view:press()
	]])
	eq(child.lua_get("did_press"), false)
	eq(child.lua_get("pressed"), false)
end

T["layout"]["canvas over a negative z canvas hides its highlights"] = function()
	run([[
		view:render(m.block({
			m.canvas({
				position = "absolute",
				top = 0,
				left = 0,
				z = -1,
				inert = true,
				width = 10,
				height = 1,
				draw = function(ctx)
					ctx:fill(0, 0, 10, 1, "#", "Comment")
				end,
			}),
			m.canvas({
				width = 6,
				height = 1,
				margin_left = 2,
				draw = function(ctx)
					ctx:text(0, 0, "ab")
				end,
			}),
		}))
	]])
	eq(lines(), { "##ab######" })
	eq(marks(), {
		{ 0, 0, 2, "Comment" },
		{ 0, 4, 10, "Comment" },
	})
end

T["layout"]["sides with nothing to size them error"] = function()
	local function mount_error(props)
		return child.lua(
			[[
			local props = ...
			props.draw = function() end
			local ok, err = pcall(view.render, view, m.canvas(props))
			return not ok and err:match("^[^\n]*") or nil
		]],
			{ props }
		)
	end
	eq(
		mount_error({ width = 4 }),
		"canvas height `auto` has nothing to size it: give cells, `full`, a share or `min_height`"
	)
	eq(
		mount_error({ width = 4, height = "fit" }),
		"canvas height `fit` has nothing to size it: give cells, `full`, a share or `min_height`"
	)
	eq(
		mount_error({ width = "fit", height = 2 }),
		"canvas width `fit` has nothing to size it: give cells, `full`, a share or `min_width`"
	)
	eq(mount_error({ height = 2 }), vim.NIL)
	eq(mount_error({ width = 4, min_height = 2 }), vim.NIL)
end

T["layout"]["a reactive side with nothing to size it errors"] = function()
	child.lua([[
		local height = m.signal(2)
		view:render(m.canvas({ width = 4, height = height, draw = function() end }))
		vim.notify = function(msg) _G.reported = msg end
		height("auto")
		reactive.flush()
	]])
	-- Effect errors are reported on the next tick.
	child.lua("vim.wait(1000, function() return _G.reported ~= nil end)")
	local err = child.lua_get("_G.reported")
	eq(type(err), "string")
	eq(err:find("canvas height `auto` has nothing to size it", 1, true) ~= nil, true)
end

return T
