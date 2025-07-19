---@module 'mini.test'
---@module 'markup'

for name, _ in pairs(package.loaded) do
	if name:match("^markup") then
		package.loaded[name] = nil
	end
end

local helpers = dofile("tests/helpers.lua")
local markup = require("markup")
local new_set = MiniTest.new_set
local expect, eq = MiniTest.expect, MiniTest.expect.equality
local log = require("markup.logger")
local child = MiniTest.new_child_neovim()
_Markup.is_dev = false

local T = new_set({
	hooks = {
		pre_once = function()
			markup = helpers.mock_markup()
		end,
		pre_case = function()
			child.restart({ "-u", "scripts/minimal_init.lua" })
			child.lua([[markup = require('markup')]])
			child.o.lines, child.o.columns = 15, 60
		end,
		post_once = function()
			child.stop()
			markup = require("markup")
		end,
	},
})

---@param element markup.Element
---@param force? boolean
local function render_and_expect_screenshot(element, force)
	child.lua("renderer = markup.Renderer()")
	child.lua(("renderer:render(%s)"):format(element))

	expect.reference_screenshot(child.get_screenshot())
end

T["render()"] = new_set()

T["render()"]["inline"] = new_set()

T["render()"]["inline"]["throws when inline element contains block element"] = function()
	local app = markup.inline({
		markup.inline("inline1 "),
		markup.block("i shouldn't be here"),
		markup.inline("inline3"),
	})

	expect.error(function()
		render_and_expect_screenshot(app)
	end)
end

T["render()"]["inline"]["renders inline with highlight"] = function()
	local app = markup.inline({
		markup.inline({ "i'm highlighted", style = { bg = "Number" } }),
		markup.inline({ " i'm not" }),
	})

	render_and_expect_screenshot(app)
end

T["render()"]["inline"]["renders multiple inline elements"] = function()
	local app = markup.inline({
		markup.inline("inline1 "),
		markup.inline("inline2 "),
		markup.inline("inline3"),
	})

	render_and_expect_screenshot(app)
end

T["render()"]["inline"]["renders elements in reversed order"] = function()
	local app = markup.inline({
		reverse = true,
		"1",
		markup.inline("2"),
		"3",
	})

	render_and_expect_screenshot(app)
end

T["render()"]["block"] = new_set()

T["render()"]["block"]["renders mixed inline and block elements"] = function()
	local app = markup.block({
		markup.inline("inline"),
		markup.inline("inline"),
		markup.block("block"),
		markup.block("i'm on a new line!"),
		markup.inline("inline"),
		markup.inline(" also inline"),
	})

	render_and_expect_screenshot(app)
end

T["render()"]["block"]["renders elements in reversed order"] = function()
	local app = markup.block({
		reverse = true,
		markup.block("1"),
		markup.block("2"),
		markup.block("3"),
	})

	render_and_expect_screenshot(app)
end

T["render()"]["block"]["renders multiple block elements"] = function()
	local app = markup.block({
		markup.block("1"),
		markup.block("2"),
		markup.block("3"),
	})

	render_and_expect_screenshot(app)
end

T["render()"]["block"]["renders nested block with inline"] = function()
	local app = markup.block({
		markup.inline("inline"),
		markup.block({
			markup.block("block2"),
			margin_left = 3,
		}),
		markup.inline("inline"),
	})

	render_and_expect_screenshot(app)
end

T["render()"]["block"]["renders only inline elements ignoring spacing"] = function()
	local app = markup.block({
		spacing = 2,
		markup.inline("inline"),
		markup.inline("inline"),
		markup.inline("inline"),
		markup.inline("inline"),
	})

	MiniTest.add_note([[
	This is done to avoid weirdy behavior.
	Ideally render tree should wrap contigious style-less inline/text elements into one,
	which would fix this while also improving performance.
	]])

	render_and_expect_screenshot(app)
end

T["render()"]["block"]["renders complex nested block"] = function()
	local app = markup.block({
		markup.inline("inline"),
		markup.block({
			markup.block("block"),
			markup.block("block"),
			markup.block("block"),
			markup.inline("text "),
			markup.inline("text "),
			markup.inline("text"),
			markup.block("block"),
			spacing = 1,
			margin_left = 2,
		}),
		markup.inline("inline"),
	})

	render_and_expect_screenshot(app)
end

T["render()"]["hflex"] = new_set()

T["render()"]["hflex"]["renders flex with nested blocks"] = function()
	local app = markup.block({
		markup.flex({
			markup.block("hello  ->  "),
			markup.block({
				markup.block("block"),
				markup.block("aaaaaaaaaaaaaaaaaa"),
				markup.block("1"),
				markup.block("2"),
				markup.block("3"),
			}),
			markup.block("123"),
		}),
		markup.inline("inline"),
	})

	render_and_expect_screenshot(app)
end

T["render()"]["hflex"]["renders flex with inline and text"] = function()
	local app = markup.flex({
		"123",
		"123",
		markup.inline("|inline|"),
		"123",
	})

	render_and_expect_screenshot(app)
end

T["render()"]["hflex"]["renders flex with inline and text and spacing"] = function()
	local app = markup.flex({
		spacing = 2,
		"123",
		"123",
		markup.inline("|inline|"),
		"123",
	})

	render_and_expect_screenshot(app)
end

T["render()"]["hflex"]["renders flex with inline and justify-center"] = function()
	local app = markup.flex({
		justify = "center",
		spacing = 1,
		markup.inline("inline"),
		markup.inline("inline"),
		markup.inline("inline"),
	})

	render_and_expect_screenshot(app)
end

T["render()"]["hflex"]["renders flex with inline and justify-end"] = function()
	local app = markup.flex({
		justify = "end",
		spacing = 1,
		markup.inline("inline"),
		markup.inline("inline"),
		markup.inline("inline"),
	})

	render_and_expect_screenshot(app)
end

T["render()"]["hflex"]["renders flex with justify-between"] = function()
	local app = markup.flex({
		justify = "between",
		markup.block("block"),
		markup.block("block"),
		markup.block("block"),
	})

	render_and_expect_screenshot(app)
end

return T
