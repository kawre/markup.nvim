---@module 'luassert'

local markup = require("markup")
local h = require("tests.helpers")

describe("markup.Component", function()
	local renderer

	before_each(function()
		renderer = h.mock(markup.Block)
	end)

	after_each(function()
		renderer.cleanup()
	end)

	it("should normalize numbers", function()
		local Component = markup.Component(function()
			return 5
		end)

		renderer(Component(), { "5" })
	end)

	it("should normalize strings", function()
		local Component = markup.Component(function()
			return "str"
		end)

		renderer(Component(), { "str" })
	end)

	it("should normalize fragments", function()
		local Component = markup.Component(function()
			return {
				5,
				"5",
				{ 5 },
				markup.Inline("123"),
				markup.Inline(5),
				markup.Block(5),
				{
					markup.Inline(5),
					markup.Block(5),
				},
				markup.Fragment({
					markup.Block(5),
				}),
			}
		end)

		renderer(Component(), {
			"5551235",
			"5",
			"5",
			"5",
			"5",
		})
	end)

	it("should handle nodes", function()
		local Component = markup.Component(function()
			return markup.Inline("123")
		end)

		renderer(Component(), {
			"123",
		})
	end)

	it("should handle nodes", function()
		renderer.set_width(5)

		local Component = markup.Component(function()
			return markup.Flex("123")
		end)

		renderer(Component(), {
			"123  ",
		})
	end)

	it("should handle nested components", function()
		local Component5 = markup.Component(function()
			return 5
		end)
		local Component4 = markup.Component(function()
			return Component5()
		end)
		local Component3 = markup.Component(function()
			return { Component4(), 5 }
		end)
		local Component2 = markup.Component(function()
			return Component3()
		end)
		local Component1 = markup.Component(function()
			return Component2()
		end)

		renderer(Component1(), { "55" })
	end)
end)
