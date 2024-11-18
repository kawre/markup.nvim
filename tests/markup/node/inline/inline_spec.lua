---@module 'luassert'

local markup = require("markup")
local h = require("tests.helpers")

describe("markup.Inline", function()
	local renderer

	before_each(function()
		renderer = h.mock(markup.Inline)
	end)

	after_each(function()
		renderer.cleanup()
	end)

	it("should render nothing", function()
		renderer({}, {
			"",
		})
	end)

	it("should render inline elements in one row", function()
		renderer({
			markup.Inline("1"),
			markup.Inline("2"),
			markup.Inline("3"),
			markup.Inline("4"),
		}, {
			"1234",
		})
	end)

	it("should render block elements one per row", function()
		renderer({
			markup.Block("1"),
			markup.Block("2"),
			markup.Block("3"),
			markup.Block("4"),
		}, {
			"1",
			"2",
			"3",
			"4",
		})
	end)

	it("should render block elements on new line", function()
		renderer({
			markup.Inline("1"),
			markup.Block("2"),
		}, {
			"1",
			"2",
		})
	end)

	it("should render elements acording to their type", function()
		renderer({
			markup.Block("1"),
			markup.Inline("2"),
			markup.Inline({
				children = {
					markup.Inline("3"),
					markup.Inline("4"),
					markup.Block("5"),
					markup.Block("5"),
					markup.Inline("4"),
					markup.Inline("4"),
				},
			}),
		}, {
			"1",
			"234",
			"5",
			"5",
			"44",
		})
	end)

	it("should become flex box", function()
		renderer.set_width(20)

		renderer({
			markup.Inline("INLINE"),
			markup.Inline({
				display = "flex",
				children = {
					markup.Inline("1"),
					markup.Inline("22"),
					markup.Inline("333"),
					markup.Inline("4444"),
					markup.Inline("55555"),
				},
			}),
		}, {
			"INLINE",
			"1                   ",
			"22                  ",
			"333                 ",
			"4444                ",
			"55555               ",
		})
	end)
end)
