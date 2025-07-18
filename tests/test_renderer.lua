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
							args = ("{ %s }"):format(table.concat(args, ", "))
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

local function render_helper(element)
	child.lua("renderer = markup.Renderer()")
	child.lua(("renderer:render(%s)"):format(element))
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

	render_helper(app)
	expect.reference_screenshot(child.get_screenshot())
end

T["render()"]["inline"] = function()
	local app = markup.inline({
		markup.inline("inline1 "),
		markup.inline("inline2 "),
		markup.inline("inline3"),
	})

	render_helper(app)
	expect.reference_screenshot(child.get_screenshot())
end

T["render()"]["disallow block elements in an inline element"] = function()
	local app = markup.inline({
		markup.inline("inline1 "),
		markup.block("i shouldn't be here"),
		markup.inline("inline3"),
	})

	expect.error(function()
		render_helper(app)
	end)
end

T["render()"]["block elements table"] = function()
	local app = markup.block({
		markup.block("1"),
		markup.block("2"),
		markup.block("3"),
	})

	render_helper(app)
	expect.reference_screenshot(child.get_screenshot())
end

return T
