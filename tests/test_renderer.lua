---@module 'mini.test'
---@module 'markup'

local helpers = dofile("tests/helpers.lua")
local m = require("markup")
local new_set = MiniTest.new_set
local expect, eq = MiniTest.expect, MiniTest.expect.equality
local child = MiniTest.new_child_neovim()

local T = new_set({
	hooks = {
		pre_once = function()
			m = helpers.mock_markup()
			child.start({ "-u", "scripts/minimal_init.lua" })
			child.lua([[
			markup = require('markup')
			Markup.window = setmetatable({}, {
				__call = function()
					return { win = vim.api.nvim_get_current_win(), buf = vim.api.nvim_get_current_buf(), id = 1, on = function() end }
				end
			})
			renderer = Markup.renderer()
			]])
		end,
		pre_case = function()
			child.o.lines, child.o.columns = 15, 60
		end,
		post_once = function()
			child.stop()
			m = require("markup")
		end,
	},
})

---@param element markup.element
---@param opts? table
local function render_and_expect_screenshot(element, opts)
	child.lua(([[renderer:render(%s)]]):format(element))
	expect.reference_screenshot(child.get_screenshot(), nil, opts)
end

T["render()"] = new_set()

T["render()"]["inline"] = new_set()

T["render()"]["inline"]["throws when inline element contains block element"] = function()
	local app = m.inline({
		m.inline("inline1 "),
		m.block("i shouldn't be here"),
		m.inline("inline3"),
	})

	expect.error(function()
		render_and_expect_screenshot(app)
	end)
end

T["render()"]["inline"]["renders inline with highlight"] = function()
	local app = m.inline({
		m.inline({ "i'm highlighted", style = "Cursor" }),
		m.inline({ " i'm not" }),
	})

	render_and_expect_screenshot(app)
end

T["render()"]["inline"]["renders inline with highlight respecting margin and padding"] = function()
	local app = m.inline({
		style = "Cursor",
		padding_left = 3,
		margin_left = 2,
		m.inline("inline"),
	})

	render_and_expect_screenshot(app)
end

T["render()"]["inline"]["renders inline with highlight respecting padding left and right"] = function()
	local app = m.inline({
		m.inline("inline"),
		m.inline({
			style = "Cursor",
			padding_left = 2,
			padding_right = 2,
			"inline",
		}),
		m.inline("inline"),
	})

	render_and_expect_screenshot(app)
end

T["render()"]["inline"]["renders multiple inline elements"] = function()
	local app = m.inline({
		m.inline("inline1 "),
		m.inline("inline2 "),
		m.inline("inline3"),
	})

	render_and_expect_screenshot(app)
end

T["render()"]["inline"]["renders elements in reversed order"] = function()
	local app = m.inline({
		reverse = true,
		"1",
		m.inline("2"),
		"3",
	})

	render_and_expect_screenshot(app)
end

T["render()"]["inline"]["renders inline elements respecing margin and padding"] = function()
	local app = m.inline({
		m.inline("inline"),
		m.inline({
			"inline",
			margin_left = 3,
			margin_right = 3,
		}),
		m.inline("inline"),
	})

	render_and_expect_screenshot(app)
end

T["render()"]["block"] = new_set()

T["render()"]["block"]["renders mixed inline and block elements"] = function()
	local app = m.block({
		m.inline("inline"),
		m.inline("inline"),
		m.block("block"),
		m.block("i'm on a new line!"),
		m.inline("inline"),
		m.inline(" also inline"),
	})

	render_and_expect_screenshot(app)
end

T["render()"]["block"]["renders elements in reversed order"] = function()
	local app = m.block({
		reverse = true,
		m.block("1"),
		m.block("2"),
		m.block("3"),
	})

	render_and_expect_screenshot(app)
end

T["render()"]["block"]["renders multiple block elements"] = function()
	local app = m.block({
		m.block("1"),
		m.block("2"),
		m.block("3"),
	})

	render_and_expect_screenshot(app)
end

T["render()"]["block"]["respects other block elements margin and padding box size"] = function()
	local app = m.block({
		m.block({
			padding_top = 1,
			padding_bottom = 1,
			m.inline("inline"),
		}),
		m.block({
			margin_top = 1,
			margin_bottom = 1,
			m.inline("inline"),
		}),
		m.block("block"),
	})

	render_and_expect_screenshot(app)
end

T["render()"]["block"]["single block with padding bottom"] = function()
	local app = m.block({
		width = 20,
		padding_bottom = 1,
		style = "Search",
		m.block({
			height = 5,
			m.block("block"),
			m.block("block"),
			m.block("block"),
			padding_left = 3,
			padding_bottom = 3,
		}),
	})

	render_and_expect_screenshot(app)
end

T["render()"]["block"]["renders nested block with inline"] = function()
	local app = m.block({
		m.inline("inline"),
		m.block({
			m.block("block2"),
			margin_left = 3,
		}),
		m.inline("inline"),
	})

	render_and_expect_screenshot(app)
end

T["render()"]["block"]["renders only inline elements ignoring spacing"] = function()
	local app = m.block({
		spacing = 2,
		m.inline("inline"),
		m.inline("inline"),
		m.inline("inline"),
		m.inline("inline"),
	})

	MiniTest.add_note([[
	This is done to avoid weirdy behavior.
	Ideally render tree should wrap contigious style-less inline/text elements into one,
	which would fix this while also improving performance.
	]])

	render_and_expect_screenshot(app)
end

T["render()"]["block"]["renders complex nested block"] = function()
	local app = m.block({
		m.inline("inline"),
		m.block({
			m.block("block"),
			m.block("block"),
			m.block("block"),
			m.inline("text "),
			m.inline("text "),
			m.inline("text"),
			m.block("block"),
			spacing = 1,
			margin_left = 2,
		}),
		m.inline("inline"),
	})

	render_and_expect_screenshot(app)
end

T["render()"]["block"]["renders block elements with height and width"] = function()
	local app = m.block({
		width = 15,
		style = "Cursor",
		spacing = 2,
		height = 10,
		m.inline("inline"),
		m.inline("inline"),
		m.block("block"),
		m.block("block"),
	})

	render_and_expect_screenshot(app)
end

T["render()"]["hflex"] = new_set()

T["render()"]["hflex"]["renders flex with nested blocks"] = function()
	local app = m.block({
		m.flex({
			m.block("hello  ->  "),
			m.block({
				m.block("block"),
				m.block("aaaaaaaaaaaaaaaaaa"),
				m.block("1"),
				m.block("2"),
				m.block("3"),
			}),
			m.block("123"),
		}),
		m.inline("inline"),
	})

	render_and_expect_screenshot(app)
end

T["render()"]["hflex"]["renders flex with inline and text"] = function()
	local app = m.flex({
		"123",
		"123",
		m.inline("|inline|"),
		"123",
	})

	render_and_expect_screenshot(app)
end

T["render()"]["hflex"]["renders flex with inline and text and spacing"] = function()
	local app = m.flex({
		spacing = 2,
		"123",
		"123",
		m.inline("|inline|"),
		"123",
	})

	render_and_expect_screenshot(app)
end

T["render()"]["hflex"]["renders flex with inline and justify-center"] = function()
	local app = m.flex({
		justify = "center",
		spacing = 1,
		m.inline("inline"),
		m.inline("inline"),
		m.inline("inline"),
	})

	render_and_expect_screenshot(app)
end

T["render()"]["hflex"]["renders flex with inline and justify-end"] = function()
	local app = m.flex({
		justify = "end",
		spacing = 1,
		m.inline("inline"),
		m.inline("inline"),
		m.inline("inline"),
	})

	render_and_expect_screenshot(app)
end

T["render()"]["hflex"]["renders flex with justify-between"] = function()
	local app = m.flex({
		justify = "between",
		m.block("block"),
		m.block("block"),
		m.block("block"),
	})

	render_and_expect_screenshot(app)
end

T["render()"]["hflex"]["renders other nested flex elements, shrinking them if they have no size provided"] = function()
	local app = m.block({
		m.flex({
			justify = "between",
			m.block("hello"),
			m.block({
				m.block("block"),
				m.block("bl"),
				style = "Cursor",
			}),
			m.inline("123"),
			m.flex({
				style = "Cursor",
				spacing = 1,
				m.block("hello"),
				m.block({
					m.block("block"),
					m.block("aaaa"),
					m.block("2"),
					m.block("3"),
				}),
				m.block("123"),
			}),
			m.block("123"),
		}),
		m.inline("inline"),
	})

	render_and_expect_screenshot(app)
end

T["render()"]["hflex"]["elements respect each other padding and margin boxes"] = function()
	local app = m.flex({
		m.inline({ "i'm highlighted", style = "Cursor" }),
		m.inline({ " i'm not" }),
		m.vflex({
			style = "Search",
			margin_top = 1,
			margin_left = 5,
			padding_right = 1,
			m.block({
				m.inline({ "inline" }),
				m.block("inline"),
			}),
		}),
		m.inline({ "i'm not" }),
	})

	render_and_expect_screenshot(app)
end

T["render()"]["hflex"]["lays out its children respecting their width"] = function()
	local app = m.flex({
		m.block("block"),
		m.flex({
			style = "Search",
			width = 20,
			padding_right = 1,
			m.block({
				m.inline({ "inline" }),
				m.block("block"),
				m.block("block"),
				m.block("block"),
			}),
		}),
		m.inline("inline"),
	})

	render_and_expect_screenshot(app)
end

T["render()"]["hflex"]["nested flex elements with size"] = function()
	local app = m.flex({
		m.block({
			m.block("block"),
			m.block("block"),
			m.block("block"),
			m.flex({
				width = 30,
				justify = "between",
				style = "Search",
				m.block("block"),
				m.block("block"),
				m.block("block"),
			}),
		}),
		m.block({
			m.block("block"),
			m.block("block"),
			m.block("block"),
		}),
	})

	render_and_expect_screenshot(app)
end

-- TODO
-- T["render()"]["hflex"]["highlight with wide and icon characters correctly"] = function()
-- 	local app = m.flex({
-- 		spacing = 1,
-- 		m.block("你今天吃了吗？"),
-- 		m.block("nerdfont", "Search"),
-- 	})
--
-- 	render_and_expect_screenshot(app)
-- end

T["render()"]["vflex"] = new_set()

T["render()"]["vflex"]["respect flex item width"] = function()
	local app = m.vflex({
		align = "center",
		m.inline("inline"),
		m.block({
			width = 30,
			style = "Search",
			m.block("block2"),
		}),
		m.inline("inline32"),
	})

	render_and_expect_screenshot(app)
end

T["render()"]["vflex"]["justify and align center with specified height"] = function()
	local app = m.vflex({
		align = "center",
		justify = "center",
		m.inline("inline"),
		m.block({
			width = 30,
			m.block("block2"),
		}),
		m.inline("inline32"),
		style = "Search",
		height = 10,
	})

	render_and_expect_screenshot(app)
end

T["render()"]["vflex"]["justify and align center without specified size"] = function()
	local app = m.vflex({
		align = "center",
		justify = "center",
		m.inline("inline"),
		m.block({
			m.block("block2"),
		}),
		m.inline("inline32"),
		style = "Search",
	})

	render_and_expect_screenshot(app)
end

T["render()"]["vflex"]["justify and align center without specified size"] = function()
	local app = m.vflex({
		align = "center",
		justify = "center",
		m.inline("inline"),
		m.block({
			m.block("block2"),
		}),
		m.inline("inline32"),
		style = "Search",
	})

	render_and_expect_screenshot(app)
end

T["render()"]["vflex"]["align end with justify center"] = function()
	local app = m.vflex({
		align = "end",
		justify = "center",
		spacing = 2,
		m.inline("inline"),
		m.block({
			m.block("block2"),
		}),
		m.inline("inline32"),
		style = "Search",
		height = 7,
	})

	render_and_expect_screenshot(app)
end

T["render()"]["vflex"]["align end with justify end"] = function()
	local app = m.vflex({
		align = "end",
		justify = "end",
		spacing = 2,
		m.inline("inline"),
		m.block({
			m.block("block2"),
		}),
		m.inline("inline32"),
		style = "Search",
		height = 10,
	})

	render_and_expect_screenshot(app)
end

T["render()"]["vflex"]["align items with stretch"] = function()
	local app = m.vflex({
		spacing = 1,
		m.block("block", "Search"),
		m.block("block", "Search"),
		m.block("block", "Search"),
		m.block("block", "Search"),
		height = 10,
	})

	render_and_expect_screenshot(app)
end

return T
