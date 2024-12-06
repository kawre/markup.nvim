---@module 'luassert'

local markup = require("markup.core")
local h = require("tests.helpers")

describe("markup.Flex", function()
	local renderer

	before_each(function()
		renderer = h.mock(markup.Flex)
	end)

	after_each(function()
		renderer.cleanup()
	end)

	it("should render nothing", function()
		renderer({}, {
			"",
		})
	end)

	it("should render inline elements one per row", function()
		renderer({
			markup.Inline("1"),
			markup.Inline("2"),
			markup.Inline("3"),
			markup.Inline("4"),
		}, {
			"1         ",
			"2         ",
			"3         ",
			"4         ",
		})
	end)

	it("should render block elements one per row", function()
		renderer({
			markup.Block("1"),
			markup.Block("2"),
			markup.Block("3"),
			markup.Block("4"),
		}, {
			"1         ",
			"2         ",
			"3         ",
			"4         ",
		})
	end)

	it("should render elements one per row", function()
		renderer({
			markup.Inline("1"),
			markup.Block("2"),
			markup.Inline("3"),
			markup.Block("4"),
			markup.Block("5"),
		}, {
			"1         ",
			"2         ",
			"3         ",
			"4         ",
			"5         ",
		})
	end)

	it("should render elements one per row with one empty line between them", function()
		renderer({
			spacing = 1,
			children = {
				markup.Inline("1"),
				markup.Block("2"),
				markup.Inline("3"),
				markup.Block("4"),
				markup.Block("5"),
			},
		}, {
			"1         ",
			"          ",
			"2         ",
			"          ",
			"3         ",
			"          ",
			"4         ",
			"          ",
			"5         ",
		})
	end)

	it("should render RowBox as inline block", function()
		renderer({
			markup.Inline("1"),
			markup.Block("2"),
			markup.Box({
				vertical = false,
				children = {
					markup.Inline("3"),
					markup.Block("3"),
				},
			}),
			markup.Block("4"),
		}, {
			"1         ",
			"2         ",
			"33        ",
			"4         ",
		})
	end)

	it("should render RowBox as inline block with one space between elements", function()
		renderer({
			markup.Inline("1"),
			markup.Block("2"),
			markup.Box({
				vertical = false,
				spacing = 1,
				children = {
					markup.Inline("3"),
					markup.Block("3"),
				},
			}),
			markup.Block("4"),
		}, {
			"1         ",
			"2         ",
			"3 3       ",
			"4         ",
		})
	end)

	it("should align elements to the start", function()
		renderer({
			align = "start",
			children = {
				markup.Inline("1"),
				markup.Block("2"),
				markup.Block("33"),
			},
		}, {
			"1         ",
			"2         ",
			"33        ",
		})
	end)

	it("should align elements in the center", function()
		renderer({
			align = "center",
			children = {
				markup.Inline("1"),
				markup.Block("2"),
				markup.Block("33"),
			},
		}, {
			"     1    ",
			"     2    ",
			"    33    ",
		})
	end)

	it("should align elements to the end", function()
		renderer({
			align = "end",
			children = {
				markup.Inline("1"),
				markup.Block("2"),
				markup.Block("33"),
			},
		}, {
			"         1",
			"         2",
			"        33",
		})
	end)

	it("should align elements to the center, but keep the boxes inner alignment", function()
		renderer({
			align = "center",
			children = {
				markup.Inline("1"),
				markup.Block("2"),
				markup.Box({
					children = {
						markup.Inline("inside"),
						markup.Block("hi"),
					},
				}),
				markup.Block("3"),
			},
		}, {
			"     1    ",
			"     2    ",
			"  inside  ",
			"  hi      ",
			"     3    ",
		})
	end)

	it("should work with large spacing", function()
		renderer({
			align = "center",
			spacing = 5,
			children = {
				markup.Inline("1"),
				markup.Box({
					children = {
						markup.Inline("inside"),
						markup.Block("hi"),
					},
				}),
				markup.Block("2"),
			},
		}, {
			"     1    ",
			"          ",
			"          ",
			"          ",
			"          ",
			"          ",
			"  inside  ",
			"  hi      ",
			"          ",
			"          ",
			"          ",
			"          ",
			"          ",
			"     2    ",
		})
	end)

	it("should work with large spacing", function()
		renderer({
			align = "end",
			spacing = 5,
			children = {
				markup.Inline("1"),
				markup.Box({
					children = {
						markup.Inline("inside"),
						markup.Block("hi"),
					},
				}),
				markup.Block("2"),
			},
		}, {
			"         1",
			"          ",
			"          ",
			"          ",
			"          ",
			"          ",
			"    inside",
			"    hi    ",
			"          ",
			"          ",
			"          ",
			"          ",
			"          ",
			"         2",
		})
	end)

	it("should handle complex nesting", function()
		renderer.set_width(26)

		renderer({
			spacing = 1,
			children = {
				markup.Inline("inline"),
				markup.Box({
					children = {
						markup.Inline("box"),
					},
				}),
				markup.Box({
					children = {
						markup.Inline("xxxxxx"),
						markup.Block("xxxx"),
						markup.Box({
							vertical = false,
							children = {
								markup.Inline("xxxxxxx"),
								markup.Box({
									children = {
										markup.Inline("inside"),
										markup.Block("hi"),
									},
								}),
							},
						}),
					},
				}),
				markup.Block("block"),
			},
		}, {
			"inline                    ",
			"                          ",
			"box                       ",
			"                          ",
			"xxxxxx                    ",
			"xxxx                      ",
			"xxxxxxxinside             ",
			"       hi                 ",
			"                          ",
			"block                     ",
		})
	end)

	it("should handle complex nesting", function()
		renderer.set_width(26)

		renderer({
			spacing = 1,
			children = {
				markup.Inline("inline"),
				markup.Box({
					children = {
						markup.Inline("box"),
					},
				}),
				markup.Box({
					children = {
						markup.Inline("xxxxxx"),
						markup.Block("xxxx"),
						markup.Box({
							vertical = false,
							spacing = 3,
							children = {
								markup.Inline("xxxxxxx"),
								markup.Box({
									children = {
										markup.Inline("inside"),
										markup.Block("hi"),
									},
								}),
							},
						}),
					},
				}),
				markup.Block("block"),
			},
		}, {
			"inline                    ",
			"                          ",
			"box                       ",
			"                          ",
			"xxxxxx                    ",
			"xxxx                      ",
			"xxxxxxx   inside          ",
			"          hi              ",
			"                          ",
			"block                     ",
		})
	end)

	it("should handle deeply nested structures with mixed alignments", function()
		renderer.set_width(30)

		renderer({
			align = "center",
			spacing = 2,
			children = {
				markup.Inline("Top"),
				markup.Box({
					align = "start",
					vertical = true,
					children = {
						markup.Inline("Start Box"),
						markup.Box({
							align = "end",
							vertical = false,
							children = {
								markup.Inline("End Row 1"),
								markup.Block("End Row 2"),
							},
						}),
						markup.Box({
							align = "center",
							vertical = true,
							spacing = 1,
							children = {
								markup.Inline("Center Column 1"),
								markup.Box({
									align = "start",
									vertical = false,
									children = {
										markup.Inline("Start Row 1"),
										markup.Block("Start Row 2"),
									},
								}),
							},
						}),
					},
				}),
				markup.Block("Bottom Block"),
			},
		}, {
			"              Top             ",
			"                              ",
			"                              ",
			"    Start Box                 ",
			"    End Row 1End Row 2        ",
			"        Center Column 1       ",
			"                              ",
			"    Start Row 1Start Row 2    ",
			"                              ",
			"                              ",
			"         Bottom Block         ",
		})
	end)

	it("should center elements", function()
		renderer.set_width(30)

		renderer({
			spacing = 3,
			align = "center",
			children = {
				markup.Inline("Title"),
				markup.Box({
					children = {
						markup.Inline("Lorem ipsum dolor sit amet"),
						markup.Inline("Lorem ipsum dolor sit amet"),
						markup.Inline("Lorem ipsum dolor sit amet"),
						markup.Inline("Lorem ipsum dolor sit amet"),
						markup.Inline("Lorem ipsum dolor sit amet"),
						markup.Inline("Lorem ipsum"),
					},
				}),
				markup.Block("Footer"),
			},
		}, {
			"             Title            ",
			"                              ",
			"                              ",
			"                              ",
			"  Lorem ipsum dolor sit amet  ",
			"  Lorem ipsum dolor sit amet  ",
			"  Lorem ipsum dolor sit amet  ",
			"  Lorem ipsum dolor sit amet  ",
			"  Lorem ipsum dolor sit amet  ",
			"  Lorem ipsum                 ",
			"                              ",
			"                              ",
			"                              ",
			"            Footer            ",
		})
	end)

	it("should put highlight at the correct position", function()
		renderer.set_width(20)

		renderer({
			children = {
				markup.Inline("1", { bold = true }),
				markup.Inline("12", { background = "orange" }),
				markup.Inline("123", { background = "aqua", color = "black", italic = true }),
				markup.Inline("1234", { background = "red" }),
			},
		}, {
			"1                   ",
			"12                  ",
			"123                 ",
			"1234                ",
		}, {
			{ 1, 0, 0 },
			{ 2, 1, 0 },
			{ 3, 2, 0 },
			{ 4, 3, 0 },
		})
	end)

	it("should put highlight at the correct position", function()
		renderer.set_width(20)

		renderer({
			align = "center",
			vertical = true,
			children = {
				markup.Inline("1", { bold = true }),
				markup.Inline("12", { background = "orange" }),
				markup.Inline("123", { background = "aqua", color = "black", italic = true }),
				markup.Inline("1234", { background = "red" }),
			},
		}, {
			"          1         ",
			"         12         ",
			"         123        ",
			"        1234        ",
		}, {
			{ 1, 0, 10 },
			{ 2, 1, 9 },
			{ 3, 2, 9 },
			{ 4, 3, 8 },
		})
	end)

	-- it("should break after text node", function()
	-- 	renderer.set_width(30)
	--
	-- 	renderer({
	-- 		"text",
	-- 		markup.Tree({
	-- 			expanded = true,
	-- 			title = "markup.tree title",
	-- 			icons = {
	-- 				collapse = "",
	-- 				indent = " ",
	-- 				indent_last = " ",
	-- 				indent_hor = " ",
	-- 			},
	-- 			children = {
	-- 				markup.Block("block"),
	-- 				markup.Block("block"),
	-- 			},
	-- 		}),
	-- 		"text",
	-- 		"text",
	-- 	}, {
	-- 		"text                          ",
	-- 		" markup.tree title           ",
	-- 		"  block                       ",
	-- 		"  block                       ",
	-- 		"texttext                      ",
	-- 	})
	-- end)

	it("should handle fragments", function()
		renderer.set_width(30)

		renderer({
			markup.Block("1"),
			markup.Inline("2"),
			markup.Inline({
				children = {
					markup.Inline("4"),
					{
						markup.Flex("3"),
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
			"1                             ",
			"2                             ",
			"4                             ",
			"3                             ",
			"4                             ",
			"5                             ",
			"5                             ",
			"444                           ",
		})
	end)

	it("should normalize text node into one", function()
		renderer.set_width(20)

		renderer({
			spacing = 2,
			children = {
				"text",
				"text",
				"text",
				markup.Block("block"),
				"text",
				"text",
				markup.Inline("inline"),
			},
		}, {
			"texttexttext        ",
			"                    ",
			"                    ",
			"block               ",
			"                    ",
			"                    ",
			"texttext            ",
			"                    ",
			"                    ",
			"inline              ",
		})
	end)
end)
