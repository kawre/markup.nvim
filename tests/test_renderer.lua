---@module 'mini.test'
---@module 'markup'

for name, _ in pairs(package.loaded) do
	if name:match("^markup") then
		package.loaded[name] = nil
	end
end

local markup = require("markup")
local new_set = MiniTest.new_set
local expect, eq = MiniTest.expect, MiniTest.expect.equality
local log = require("markup.logger")
local child = MiniTest.new_child_neovim()
_Markup.is_dev = false

local T = new_set({
	hooks = {
		pre_once = function()
			setmetatable(markup, {
				__index = function(_, key)
					return function(args)
						if type(args) == "table" then
							local parts = {}
							for _, v in ipairs(args) do
								table.insert(parts, v)
							end
							for k, v in pairs(args) do
								if type(k) ~= "number" then
									table.insert(parts, ("%s = %s"):format(k, v))
								end
							end
							args = ("{ %s }"):format(table.concat(parts, ", "))
						else
							args = ("\"%s\""):format(args)
						end

						return ("markup.%s(%s)"):format(key, args)
					end
				end,
			})
		end,
		pre_case = function()
			child.restart({ "-u", "scripts/minimal_init.lua" })
			child.lua([[markup = require('markup')]])
			child.o.lines, child.o.columns = 15, 60
		end,
		post_once = function()
			child.stop()
			package.loaded["markup"] = nil
			markup = require("markup")
		end,
	},
})

T["render()"] = new_set({})

local function render_and_expect_screenshot(element)
	child.lua("renderer = markup.Renderer()")
	child.lua(("renderer:render(%s)"):format(element))

	expect.reference_screenshot(child.get_screenshot())
end

T["render()"]["handles block|inline logic"] = function()
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

T["render()"]["inline"] = function()
	local app = markup.inline({
		markup.inline("inline1 "),
		markup.inline("inline2 "),
		markup.inline("inline3"),
	})

	render_and_expect_screenshot(app)
end

T["render()"]["disallow block elements in an inline element"] = function()
	local app = markup.inline({
		markup.inline("inline1 "),
		markup.block("i shouldn't be here"),
		markup.inline("inline3"),
	})

	expect.error(function()
		render_and_expect_screenshot(app)
	end)
end

T["render()"]["block elements table"] = function()
	local app = markup.block({
		markup.block("1"),
		markup.block("2"),
		markup.block("3"),
	})

	render_and_expect_screenshot(app)
end

T["render()"]["nested block elements"] = function()
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

T["render()"]["block element spacing"] = function()
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

return T
