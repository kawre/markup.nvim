local markup = require("markup")

describe("ColumnBox Renderer", function()
	local h = require("tests.helpers")

	---@type table, markup.Renderer
	local window, renderer

	before_each(function()
		window = h.open_window()
		renderer = h.bind_renderer(window)
	end)

	after_each(function()
		h.close_window(window)
	end)

	local function ColumnBoxRenderer(props, lines)
		local default = {
			direction = "column",
			children = props,
		}

		if props.children then
			default.children = props.children
		end

		for key, value in pairs(props) do
			default[key] = value
		end

		renderer({
			child = markup.Box(default),
		}):render()
		h.assert_lines(window, lines)
	end

	it("should render inline elements one per row", function()
		ColumnBoxRenderer({
			markup.Inline("1"),
			markup.Inline("2"),
			markup.Inline("3"),
			markup.Inline("4"),
		}, {
			"1        ",
			"2        ",
			"3        ",
			"4        ",
		})
	end)

	it("should render block elements one per row", function()
		ColumnBoxRenderer({
			markup.Block("1"),
			markup.Block("2"),
			markup.Block("3"),
			markup.Block("4"),
		}, {
			"1        ",
			"2        ",
			"3        ",
			"4        ",
		})
	end)

	it("should render elements one per row", function()
		ColumnBoxRenderer({
			markup.Inline("1"),
			markup.Block("2"),
			markup.Inline("3"),
			markup.Block("4"),
			markup.Block("5"),
		}, {
			"1        ",
			"2        ",
			"3        ",
			"4        ",
			"5        ",
		})
	end)

	it("should render elements one per row with one empty line between them", function()
		ColumnBoxRenderer({
			spacing = 1,
			children = {
				markup.Inline("1"),
				markup.Block("2"),
				markup.Inline("3"),
				markup.Block("4"),
				markup.Block("5"),
			},
		}, {
			"1        ",
			"         ",
			"2        ",
			"         ",
			"3        ",
			"         ",
			"4        ",
			"         ",
			"5        ",
		})
	end)

	it("should render RowBox as inline block", function()
		ColumnBoxRenderer({
			markup.Inline("1"),
			markup.Block("2"),
			markup.Box({
				direction = "row",
				children = {
					markup.Inline("3"),
					markup.Block("3"),
				},
			}),
			markup.Block("4"),
		}, {
			"1        ",
			"2        ",
			"33       ",
			"4        ",
		})
	end)

	it("should render RowBox as inline block with one space between elements", function()
		ColumnBoxRenderer({
			markup.Inline("1"),
			markup.Block("2"),
			markup.Box({
				direction = "row",
				spacing = 1,
				children = {
					markup.Inline("3"),
					markup.Block("3"),
				},
			}),
			markup.Block("4"),
		}, {
			"1        ",
			"2        ",
			"3 3      ",
			"4        ",
		})
	end)
end)
