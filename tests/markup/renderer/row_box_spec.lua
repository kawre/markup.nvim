local markup = require("markup")
local h = require("tests.helpers")

describe("RowBox Renderer", function()
	---@type table, markup.Renderer
	local window, renderer

	before_each(function()
		window = h.open_window()
		renderer = h.bind_renderer(window)
	end)

	after_each(function()
		h.close_window(window)
	end)

	it("should render inline elements in one row", function()
		renderer({
			child = markup.Box({
				direction = "row",
				children = {
					markup.Inline("1"),
					markup.Inline("2"),
					markup.Inline("3"),
					markup.Inline("4"),
				},
			}),
		}):render()

		h.assert_lines(window, {
			"1234     ",
		})
	end)

	it("should render block elements in one row", function()
		renderer({
			child = markup.Box({
				direction = "row",
				children = {
					markup.Block("1"),
					markup.Block("2"),
					markup.Block("3"),
					markup.Block("4"),
				},
			}),
		}):render()

		h.assert_lines(window, {
			"1234     ",
		})
	end)

	it("should render elements in one row", function()
		renderer({
			child = markup.Box({
				direction = "row",
				children = {
					markup.Inline("1"),
					markup.Block("2"),
					markup.Inline("3"),
					markup.Block("4"),
					markup.Block("5"),
				},
			}),
		}):render()

		h.assert_lines(window, {
			"12345    ",
		})
	end)

	it("should render elements in one row with one space between them", function()
		renderer({
			child = markup.Box({
				direction = "row",
				spacing = 1,
				children = {
					markup.Inline("1"),
					markup.Block("2"),
					markup.Inline("3"),
					markup.Block("4"),
					markup.Block("5"),
				},
			}),
		}):render()

		h.assert_lines(window, {
			"1 2 3 4 5",
		})
	end)

	it("should render ColumnBox as inline block", function()
		renderer({
			child = markup.Box({
				direction = "row",
				children = {
					markup.Inline("1"),
					markup.Block("2"),
					markup.Box({
						children = {
							markup.Inline("3"),
							markup.Block("3"),
						},
					}),
					markup.Block("4"),
				},
			}),
		}):render()

		h.assert_lines(window, {
			"1234     ",
			"  3      ",
		})
	end)
end)
