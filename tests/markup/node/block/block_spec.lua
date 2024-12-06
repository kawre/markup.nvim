---@module 'luassert'

local markup = require("markup.core")
local h = require("tests.helpers")

describe("markup.Block", function()
	local renderer

	before_each(function()
		renderer = h.mock(markup.Block)
	end)

	after_each(function()
		renderer.cleanup()
	end)

	it("should render nothing", function()
		renderer(nil, {
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

	it("should handle fragments", function()
		renderer({
			markup.Block("1"),
			markup.Inline("2"),
			markup.Inline({
				children = {
					markup.Inline("4"),
					{
						markup.Inline("3"),
						markup.Inline("4"),
						markup.Block("5"),
						{
							markup.Block("5"),
						},
					},
					{
						markup.Inline("4"),
						markup.Inline("4"),
					},
					markup.Inline("4"),
				},
			}),
		}, {
			"1",
			"2434",
			"5",
			"5",
			"444",
		})
	end)

	it("should become flex box", function()
		renderer.set_width(20)

		renderer({
			display = "flex",
			children = {
				markup.Inline("1"),
				markup.Inline("22"),
				markup.Inline("333"),
				markup.Inline("4444"),
				markup.Inline("55555"),
			},
		}, {
			"1                   ",
			"22                  ",
			"333                 ",
			"4444                ",
			"55555               ",
		})
	end)

	it("should handle components", function()
		local TextComponent = markup.Component(function(self)
			return markup.Block(self.props.text)
		end)

		renderer({
			children = {
				markup.Inline("1"),
				markup.Inline("22"),
				TextComponent({ text = "333" }),
				markup.Inline("1"),
				markup.Inline("22"),
			},
		}, {
			"122",
			"333",
			"122",
		})
	end)

	it("should handle components with fragments", function()
		local TextComponent = markup.Component(function(self)
			return markup.Block(self.props.text)
		end)

		renderer({
			children = {
				markup.Inline("1"),
				{
					markup.Inline("22"),
					TextComponent({ text = "333" }),
				},
				markup.Inline("1"),
				markup.Inline("22"),
			},
		}, {
			"122",
			"333",
			"122",
		})
	end)

	it("should render components while preserving the old order", function()
		local TreeNode = markup.Component(function(self)
			return markup.Block({
				markup.Block("TreeNode " .. self.props),
			})
		end)

		renderer({
			children = {
				markup.Block("block1"),
				TreeNode(1),
				TreeNode(2),
				markup.Block("block2"),
				TreeNode(3),
				markup.Block("block3"),
				TreeNode(4),
			},
		}, {
			"block1",
			"TreeNode 1",
			"TreeNode 2",
			"block2",
			"TreeNode 3",
			"block3",
			"TreeNode 4",
		})
	end)
end)
