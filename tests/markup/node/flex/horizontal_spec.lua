---@module 'luassert'

local markup = require("markup")
local h = require("tests.helpers")

describe("markup.HFlex", function()
	local renderer

	before_each(function()
		renderer = h.mock(markup.HFlex)
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
			"1234      ",
		})
	end)

	it("should render block elements in one row", function()
		renderer({
			markup.Block("1"),
			markup.Block("2"),
			markup.Block("3"),
			markup.Block("4"),
		}, {
			"1234      ",
		})
	end)

	it("should render elements in one row", function()
		renderer({
			markup.Inline("1"),
			markup.Block("2"),
			markup.Inline("3"),
			markup.Block("4"),
			markup.Block("5"),
		}, {
			"12345     ",
		})
	end)

	it("should render elements in one row with one space between them", function()
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
			"1 2 3 4 5 ",
		})
	end)

	it("should render ColumnBox as inline block", function()
		renderer({
			markup.Inline("1"),
			markup.Block("2"),
			markup.Box({
				children = {
					markup.Inline("3"),
					markup.Block("3"),
				},
			}),
			markup.Block("4"),
		}, {
			"1234      ",
			"  3       ",
		})
	end)

	it("should render Box as inline block", function()
		renderer({
			markup.Box({
				children = {
					markup.Block("1"),
				},
			}),
			markup.Box({
				children = {
					markup.Block("2"),
					markup.Block("2"),
				},
			}),
			markup.Box({
				children = {
					markup.Block("3"),
					markup.Block("3"),
					markup.Block("3"),
				},
			}),
		}, {
			"123       ",
			" 23       ",
			"  3       ",
		})
	end)

	it("should add spacing between inline blocks", function()
		renderer.set_width(20)

		renderer({
			spacing = 2,
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
				markup.Inline("3"),
			},
		}, {
			"   1  2  inside  3  ",
			"         hi         ",
		})
	end)

	it("should add spacing between inline blocks", function()
		renderer.set_width(20)

		renderer({
			spacing = 2,
			align = "start",
			children = {
				markup.Inline("1"),
				markup.Block("2"),
				markup.Box({
					children = {
						markup.Inline("inside"),
						markup.Block("hi"),
					},
				}),
				markup.Inline("3"),
			},
		}, {
			"1  2  inside  3     ",
			"      hi            ",
		})
	end)

	it("should add spacing between inline blocks", function()
		renderer.set_width(20)

		renderer({
			spacing = 2,
			align = "end",
			children = {
				markup.Inline("1"),
				markup.Block("2"),
				markup.Box({
					children = {
						markup.Inline("inside"),
						markup.Block("hi"),
					},
				}),
				markup.Inline("3"),
			},
		}, {
			"     1  2  inside  3",
			"           hi       ",
		})
	end)

	it("should add spacing between inline blocks", function()
		renderer.set_width(20)

		renderer({
			align = "center",
			spacing = 1,
			children = {
				markup.Inline("1"),
				markup.Box({
					spacing = 2,
					children = {
						markup.Inline("inside"),
						markup.Block("hi"),
					},
				}),
				markup.Box({
					children = {
						markup.Inline("3"),
						markup.Inline("33"),
						markup.Inline("3"),
					},
				}),
			},
		}, {
			"     1 inside 3     ",
			"              33    ",
			"              3     ",
			"       hi           ",
		})
	end)

	it("should add spacing between inline blocks", function()
		renderer.set_width(20)

		renderer({
			align = "center",
			spacing = 1,
			children = {
				markup.Box({
					align = "end",
					children = {
						markup.Inline("3"),
						markup.Inline("33"),
						markup.Inline("3"),
					},
				}),
				markup.Inline("1"),
				markup.Box({
					children = {
						markup.Inline("inside"),
						markup.Block("hi"),
					},
				}),
			},
		}, {
			"      3 1 inside    ",
			"     33   hi        ",
			"      3             ",
		})
	end)

	it("should add spacing between inline blocks", function()
		renderer.set_width(20)

		renderer({
			align = "end",
			spacing = 1,
			children = {
				markup.Box({
					align = "end",
					children = {
						markup.Inline("3"),
						markup.Inline("33"),
						markup.Inline("3"),
					},
				}),
				markup.Inline("1"),
				markup.Box({
					children = {
						markup.Inline("inside"),
						markup.Block("hi"),
					},
				}),
			},
		}, {
			"          3 1 inside",
			"         33   hi    ",
			"          3         ",
		})
	end)

	it("should add spacing between inline blocks", function()
		renderer.set_width(20)

		renderer({
			align = "start",
			spacing = 1,
			children = {
				markup.Box({
					align = "end",
					children = {
						markup.Inline("3"),
						markup.Inline("33"),
						markup.Inline("3"),
					},
				}),
				markup.Inline("1"),
				markup.Box({
					children = {
						markup.Inline("inside"),
						markup.Block("hi"),
					},
				}),
			},
		}, {
			" 3 1 inside         ",
			"33   hi             ",
			" 3                  ",
		})
	end)

	it("should handle complex nesting", function()
		renderer.set_width(32)

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
			"inline box xxxxxx        block  ",
			"           xxxx                 ",
			"           xxxxxxxinside        ",
			"                  hi            ",
		})
	end)

	it("should handle complex spacing", function()
		renderer.set_width(80)

		renderer({
			align = "start",
			vertical = false,
			margin = { 1, 2 },
			spacing = 5,
			children = {
				markup.Inline({
					padding = { 0, 1 },
					children = "inline",
				}, { background = "red" }),
				markup.Inline("inline"),
				markup.Box({
					margin = 1,
					padding = { 1, 2 },
					style = {
						color = "blue",
						background = "white",
					},
					children = {
						markup.Inline("inline"),
						markup.Inline("123123"),
						markup.Inline("inline"),
						markup.Inline("inline"),
						markup.Inline("inline"),
						markup.Inline("inline"),
						markup.Inline("inline"),
						markup.Inline("inline"),
						markup.Inline("inline"),
						markup.Inline("inline"),
						markup.Inline("inline"),
						markup.Inline("inline"),
						markup.Inline("inline"),
						markup.Inline("inline"),
						markup.Inline("inline"),
						markup.Inline("inline"),
						markup.Inline("inline"),
						markup.Inline("inline"),
						markup.Inline("inline"),
						markup.Inline("inline"),
						markup.Inline("inline"),
						markup.Inline("inline"),
						markup.Inline("inline"),
						markup.Inline("inline"),
						markup.Inline("inline"),
						markup.Inline("inline"),
						markup.Inline("inline"),
						markup.Inline("inline"),
						markup.Inline("inline"),
						markup.Inline("inline"),
						markup.Inline("inline"),
						markup.Inline("inline"),
						markup.Inline("123123"),
						markup.Inline("inline"),
						markup.Inline("123123"),
						markup.Inline("inline"),
						markup.Inline("123123"),
						markup.Inline("inline"),
						markup.Inline("123123"),
						markup.Inline("inline"),
						markup.Inline("123123"),
						markup.Inline("inline"),
						markup.Inline("123123"),
						markup.Inline("inline"),
						markup.Inline("123123"),
						markup.Inline("inline"),
						markup.Inline("123123"),
						markup.Inline("inline"),
						markup.Inline("123123"),
						markup.Inline("inline"),
						markup.Inline("123123"),
						markup.Inline("inline"),
						markup.Inline("123123"),
						markup.Inline("inline"),
						markup.Inline("123123"),
						markup.Inline("inline"),
						markup.Inline("123123"),
						markup.Inline("inline"),
						markup.Inline("123123"),
						markup.Inline("inline"),
						markup.Inline("123123"),
						markup.Inline("inline"),
						markup.Inline("123123"),
						markup.Inline("inline"),
						markup.Inline("123123"),
						markup.Inline("inline"),
						markup.Inline("123123"),
						markup.Inline("inline"),
						markup.Inline("123123"),
						markup.Inline("inline"),
						markup.Inline("123123"),
						markup.Inline("inline"),
						markup.Inline("123123"),
						markup.Inline("inline"),
						markup.Inline("123123"),
						markup.Inline("inline"),
						markup.Inline("123123"),
						markup.Inline("inline"),
						markup.Inline("123123"),
						markup.Inline("inline"),
						markup.Inline("123123"),
						markup.Inline("inline"),
						markup.Inline("123123"),
						markup.Inline("inline"),
						markup.Inline("123123"),
						markup.Inline("inline"),
						markup.Inline("123123"),
						markup.Inline("inline"),
						markup.Inline("123123"),
						markup.Inline("inline"),
					},
				}),
				markup.Box({
					margin = 1,
					padding = { 1, 2 },
					style = {
						background = "aqua",
						color = "black",
						bold = true,
					},
					children = {
						markup.Inline("inline"),
						markup.Inline("123123"),
						markup.Inline("inline"),
						markup.Inline("inline"),
						markup.Inline("inline"),
						markup.Inline("inline"),
						markup.Inline("inline"),
						markup.Inline("inline"),
						markup.Inline("inline"),
						markup.Inline("inline"),
						markup.Inline("inline"),
						markup.Inline("inline"),
						markup.Inline("inline"),
						markup.Inline("inline"),
						markup.Inline("inline"),
						markup.Inline("inline"),
						markup.Inline("inline"),
						markup.Inline("inline"),
						markup.Inline("inline"),
						markup.Inline("inline"),
						markup.Inline("inline"),
						markup.Inline("inline"),
						markup.Inline("inline"),
						markup.Inline("inline"),
						markup.Inline("inline"),
						markup.Inline("inline"),
						markup.Inline("inline"),
						markup.Inline("inline"),
						markup.Inline("inline"),
						markup.Inline("inline"),
						markup.Inline("inline"),
						markup.Inline("inline"),
						markup.Inline("123123"),
						markup.Inline("inline"),
						markup.Inline("123123"),
						markup.Inline("inline"),
						markup.Inline("123123"),
						markup.Inline("inline"),
						markup.Inline("123123"),
						markup.Inline("inline"),
						markup.Inline("123123"),
						markup.Inline("inline"),
						markup.Inline("123123"),
						markup.Inline("inline"),
						markup.Inline("123123"),
						markup.Inline("inline"),
						markup.Inline("123123"),
						markup.Inline("inline"),
						markup.Inline("123123"),
						markup.Inline("inline"),
						markup.Inline("123123"),
						markup.Inline("inline"),
						markup.Inline("123123"),
						markup.Inline("inline"),
						markup.Inline("123123"),
						markup.Inline("inline"),
						markup.Inline("123123"),
						markup.Inline("inline"),
						markup.Inline("123123"),
						markup.Inline("inline"),
						markup.Inline("123123"),
						markup.Inline("inline"),
						markup.Inline("123123"),
						markup.Inline("inline"),
						markup.Inline("123123"),
						markup.Inline("inline"),
						markup.Inline("123123"),
						markup.Inline("inline"),
						markup.Inline("123123"),
						markup.Inline("inline"),
						markup.Inline("123123"),
						markup.Inline("inline"),
						markup.Inline("123123"),
						markup.Inline("inline"),
						markup.Inline("123123"),
						markup.Inline("inline"),
						markup.Inline("123123"),
						markup.Inline("inline"),
						markup.Inline("123123"),
						markup.Inline("inline"),
						markup.Inline("123123"),
						markup.Inline("inline"),
						markup.Inline("123123"),
						markup.Inline("inline"),
						markup.Inline("123123"),
						markup.Inline("inline"),
						markup.Inline("123123"),
						markup.Inline("inline"),
						markup.Inline("123123"),
						markup.Inline("inline"),
					},
				}),
				markup.Box({
					margin = 0,
					padding = { 1, 5 },
					style = {
						background = "yellow",
						color = "black",
						bold = true,
					},
					children = {
						markup.Inline("inline"),
						markup.Inline("123123"),
						markup.Inline("inline"),
						markup.Inline("inline"),
						markup.Inline("inline"),
						markup.Inline("inline"),
						markup.Inline("inline"),
						markup.Inline("inline"),
						markup.Inline("inline"),
						markup.Inline("inline"),
						markup.Inline("inline"),
						markup.Inline("inline"),
						markup.Inline("inline"),
						markup.Inline("inline"),
						markup.Inline("inline"),
						markup.Inline("inline"),
						markup.Inline("inline"),
						markup.Inline("inline"),
						markup.Inline("inline"),
						markup.Inline("inline"),
						markup.Inline("inline"),
						markup.Inline("inline"),
						markup.Inline("inline"),
						markup.Inline("inline"),
						markup.Inline("inline"),
						markup.Inline("inline"),
						markup.Inline("inline"),
						markup.Inline("inline"),
						markup.Inline("inline"),
						markup.Inline("inline"),
						markup.Inline("inline"),
						markup.Inline("inline"),
						markup.Inline("123123"),
						markup.Inline("inline"),
						markup.Inline("123123"),
						markup.Inline("inline"),
						markup.Inline("123123"),
						markup.Inline("inline"),
						markup.Inline("123123"),
						markup.Inline("inline"),
						markup.Inline("123123"),
						markup.Inline("inline"),
						markup.Inline("123123"),
						markup.Inline("inline"),
						markup.Inline("123123"),
						markup.Inline("inline"),
						markup.Inline("123123"),
						markup.Inline("inline"),
						markup.Inline("123123"),
						markup.Inline("inline"),
						markup.Inline("123123"),
						markup.Inline("inline"),
						markup.Inline("123123"),
						markup.Inline("inline"),
						markup.Inline("123123"),
						markup.Inline("inline"),
						markup.Inline("123123"),
						markup.Inline("inline"),
						markup.Inline("123123"),
						markup.Inline("inline"),
						markup.Inline("123123"),
						markup.Inline("inline"),
						markup.Inline("123123"),
						markup.Inline("inline"),
						markup.Inline("123123"),
						markup.Inline("inline"),
						markup.Inline("123123"),
						markup.Inline("inline"),
						markup.Inline("123123"),
						markup.Inline("inline"),
						markup.Inline("123123"),
						markup.Inline("inline"),
						markup.Inline("123123"),
						markup.Inline("inline"),
						markup.Inline("123123"),
						markup.Inline("inline"),
						markup.Inline("123123"),
						markup.Inline("inline"),
						markup.Inline("123123"),
						markup.Inline("inline"),
						markup.Inline("123123"),
						markup.Inline("inline"),
						markup.Inline("123123"),
						markup.Inline("inline"),
						markup.Inline("123123"),
						markup.Inline("inline"),
						markup.Inline("123123"),
						markup.Inline("inline"),
						markup.Inline("123123"),
						markup.Inline("inline"),
					},
				}),
			},
		}, {

			"                                                                                ",
			"   inline      inline                                                           ",
			"                                                                 inline         ",
			"                             inline           inline             123123         ",
			"                             123123           123123             inline         ",
			"                             inline           inline             inline         ",
			"                             inline           inline             inline         ",
			"                             inline           inline             inline         ",
			"                             inline           inline             inline         ",
			"                             inline           inline             inline         ",
			"                             inline           inline             inline         ",
			"                             inline           inline             inline         ",
			"                             inline           inline             inline         ",
			"                             inline           inline             inline         ",
			"                             inline           inline             inline         ",
			"                             inline           inline             inline         ",
			"                             inline           inline             inline         ",
			"                             inline           inline             inline         ",
			"                             inline           inline             inline         ",
			"                             inline           inline             inline         ",
			"                             inline           inline             inline         ",
			"                             inline           inline             inline         ",
			"                             inline           inline             inline         ",
			"                             inline           inline             inline         ",
			"                             inline           inline             inline         ",
			"                             inline           inline             inline         ",
			"                             inline           inline             inline         ",
			"                             inline           inline             inline         ",
			"                             inline           inline             inline         ",
			"                             inline           inline             inline         ",
			"                             inline           inline             inline         ",
			"                             inline           inline             inline         ",
			"                             inline           inline             inline         ",
			"                             inline           inline             inline         ",
			"                             inline           inline             123123         ",
			"                             123123           123123             inline         ",
			"                             inline           inline             123123         ",
			"                             123123           123123             inline         ",
			"                             inline           inline             123123         ",
			"                             123123           123123             inline         ",
			"                             inline           inline             123123         ",
			"                             123123           123123             inline         ",
			"                             inline           inline             123123         ",
			"                             123123           123123             inline         ",
			"                             inline           inline             123123         ",
			"                             123123           123123             inline         ",
			"                             inline           inline             123123         ",
			"                             123123           123123             inline         ",
			"                             inline           inline             123123         ",
			"                             123123           123123             inline         ",
			"                             inline           inline             123123         ",
			"                             123123           123123             inline         ",
			"                             inline           inline             123123         ",
			"                             123123           123123             inline         ",
			"                             inline           inline             123123         ",
			"                             123123           123123             inline         ",
			"                             inline           inline             123123         ",
			"                             123123           123123             inline         ",
			"                             inline           inline             123123         ",
			"                             123123           123123             inline         ",
			"                             inline           inline             123123         ",
			"                             123123           123123             inline         ",
			"                             inline           inline             123123         ",
			"                             123123           123123             inline         ",
			"                             inline           inline             123123         ",
			"                             123123           123123             inline         ",
			"                             inline           inline             123123         ",
			"                             123123           123123             inline         ",
			"                             inline           inline             123123         ",
			"                             123123           123123             inline         ",
			"                             inline           inline             123123         ",
			"                             123123           123123             inline         ",
			"                             inline           inline             123123         ",
			"                             123123           123123             inline         ",
			"                             inline           inline             123123         ",
			"                             123123           123123             inline         ",
			"                             inline           inline             123123         ",
			"                             123123           123123             inline         ",
			"                             inline           inline             123123         ",
			"                             123123           123123             inline         ",
			"                             inline           inline             123123         ",
			"                             123123           123123             inline         ",
			"                             inline           inline             123123         ",
			"                             123123           123123             inline         ",
			"                             inline           inline             123123         ",
			"                             123123           123123             inline         ",
			"                             inline           inline             123123         ",
			"                             123123           123123             inline         ",
			"                             inline           inline             123123         ",
			"                             123123           123123             inline         ",
			"                             inline           inline             123123         ",
			"                             123123           123123             inline         ",
			"                             inline           inline                            ",
			"                                                                                ",
			"                                                                                ",
			"                                                                                ",
		})
	end)

	it("should put highlight at the correct position", function()
		renderer.set_width(20)

		renderer({
			markup.Inline("1", { bold = true }),
			markup.Inline("12", { background = "orange" }),
			markup.Inline("123", { background = "aqua", color = "black", italic = true }),
			markup.Inline("1234", { background = "red" }),
		}, {
			"1121231234          ",
		}, {
			{ 1, 0, 0 },
			{ 2, 0, 1 },
			{ 3, 0, 3 },
			{ 4, 0, 6 },
		})
	end)

	it("...", function()
		renderer.set_width(80)

		renderer({
			style = { background = "blue" },
			align = "start",
			spacing = 5,
			children = {
				markup.Flex({
					align = "start",
					children = {
						markup.Block("Title2"),
						markup.Block("1231233333"),
					},
				}),
				markup.Flex({
					style = { background = "aqua", color = "black" },
					padding = { 1, 2 },
					-- margin = 2,
					-- align = "end",
					children = {
						markup.Inline("Title"),
						markup.Inline("1231233333333333333"),
					},
				}),
				markup.Flex({
					align = "start",
					children = {
						markup.Block("Title2"),
						markup.Block("1231233333"),
					},
				}),
				markup.Flex({
					style = { background = "aqua", color = "black" },
					padding = { 1, 2 },
					-- margin = 2,
					-- align = "end",
					children = {
						markup.Inline("Title"),
						markup.Inline("1231233333333333333"),
					},
				}),
				markup.Flex({
					align = "start",
					children = {
						markup.Block("Title2"),
						markup.Block("1231233333"),
					},
				}),
				markup.Flex({
					style = { background = "aqua", color = "black" },
					padding = { 1, 2 },
					-- margin = 2,
					-- align = "end",
					children = {
						markup.Inline("Title"),
						markup.Inline("1231233333333333333"),
					},
				}),
				markup.Flex({
					align = "start",
					children = {
						markup.Block("Title2"),
						markup.Block("1231233333"),
					},
				}),
				markup.Flex({
					style = { background = "aqua", color = "black" },
					padding = { 1, 2 },
					-- margin = 2,
					-- align = "end",
					children = {
						markup.Inline("Title"),
						markup.Inline("1231233333333333333"),
					},
				}),
				markup.Flex({
					align = "start",
					children = {
						markup.Block("Title2"),
						markup.Block("1231233333"),
					},
				}),
				markup.Flex({
					style = { background = "aqua", color = "black" },
					padding = { 1, 2 },
					-- margin = 2,
					-- align = "end",
					children = {
						markup.Inline("Title"),
						markup.Inline("1231233333333333333"),
					},
				}),
				markup.Flex({
					align = "start",
					children = {
						markup.Block("Title2"),
						markup.Block("1231233333"),
					},
				}),
				markup.Flex({
					style = { background = "aqua", color = "black" },
					padding = { 1, 2 },
					-- margin = 2,
					-- align = "end",
					children = {
						markup.Inline("Title"),
						markup.Inline("1231233333333333333"),
					},
				}),
				markup.Flex({
					align = "start",
					children = {
						markup.Block("Title2"),
						markup.Block("1231233333"),
					},
				}),
				markup.Flex({
					style = { background = "aqua", color = "black" },
					padding = { 1, 2 },
					-- margin = 2,
					-- align = "end",
					children = {
						markup.Inline("Title"),
						markup.Inline("1231233333333333333"),
					},
				}),
				markup.Flex({
					align = "start",
					children = {
						markup.Block("Title2"),
						markup.Block("1231233333"),
					},
				}),
				markup.Flex({
					style = { background = "aqua", color = "black" },
					padding = { 1, 2 },
					-- margin = 2,
					-- align = "end",
					children = {
						markup.Inline("Title"),
						markup.Inline("1231233333333333333"),
					},
				}),
				markup.Flex({
					style = { background = "aqua", color = "black" },
					padding = { 1, 2 },
					-- margin = 2,
					-- align = "end",
					children = {
						markup.Inline("Title"),
						markup.Inline("1231233333333333333"),
					},
				}),
				markup.Flex({
					align = "start",
					children = {
						markup.Block("Title2"),
						markup.Block("1231233333"),
					},
				}),
				markup.Flex({
					style = { background = "aqua", color = "black" },
					padding = { 1, 2 },
					-- margin = 2,
					-- align = "end",
					children = {
						markup.Inline("Title"),
						markup.Inline("1231233333333333333"),
					},
				}),
				markup.Flex({
					align = "start",
					children = {
						markup.Block("Title2"),
						markup.Block("1231233333"),
					},
				}),
				markup.Flex({
					style = { background = "aqua", color = "black" },
					padding = { 1, 2 },
					-- margin = 2,
					-- align = "end",
					children = {
						markup.Inline("Title"),
						markup.Inline("1231233333333333333"),
					},
				}),
				markup.Flex({
					align = "start",
					children = {
						markup.Block("Title2"),
						markup.Block("1231233333"),
					},
				}),
				markup.Flex({
					style = { background = "aqua", color = "black" },
					padding = { 1, 2 },
					-- margin = 2,
					-- align = "end",
					children = {
						markup.Inline("Title"),
						markup.Inline("1231233333333333333"),
					},
				}),
				markup.Flex({
					align = "start",
					children = {
						markup.Block("Title2"),
						markup.Block("1231233333"),
					},
				}),
				markup.Flex({
					style = { background = "aqua", color = "black" },
					padding = { 1, 2 },
					-- margin = 2,
					-- align = "end",
					children = {
						markup.Inline("Title"),
						markup.Inline("1231233333333333333"),
					},
				}),
				markup.Flex({
					style = { background = "aqua", color = "black" },
					padding = { 1, 2 },
					-- margin = 2,
					-- align = "end",
					children = {
						markup.Inline("Title"),
						markup.Inline("1231233333333333333"),
					},
				}),
				markup.Flex({
					align = "start",
					children = {
						markup.Block("Title2"),
						markup.Block("1231233333"),
					},
				}),
				markup.Flex({
					style = { background = "aqua", color = "black" },
					padding = { 1, 2 },
					-- margin = 2,
					-- align = "end",
					children = {
						markup.Inline("Title"),
						markup.Inline("1231233333333333333"),
					},
				}),
				markup.Flex({
					align = "start",
					children = {
						markup.Block("Title2"),
						markup.Block("1231233333"),
					},
				}),
				markup.Flex({
					style = { background = "aqua", color = "black" },
					padding = { 1, 2 },
					-- margin = 2,
					-- align = "end",
					children = {
						markup.Inline("Title"),
						markup.Inline("1231233333333333333"),
					},
				}),
				markup.Flex({
					align = "start",
					children = {
						markup.Block("Title2"),
						markup.Block("1231233333"),
					},
				}),
				markup.Flex({
					style = { background = "aqua", color = "black" },
					padding = { 1, 2 },
					-- margin = 2,
					-- align = "end",
					children = {
						markup.Inline("Title"),
						markup.Inline("1231233333333333333"),
					},
				}),
			},
		}, {
			"Title2                                     Title2                                     Title2                                     Title2                                     Title2                                     Title2                                     Title2                                     Title2                                                                 Title2                                     Title2                                     Title2                                     Title2                                                                 Title2                                     Title2                                     Title2                                ",
			"1231233333       Title                     1231233333       Title                     1231233333       Title                     1231233333       Title                     1231233333       Title                     1231233333       Title                     1231233333       Title                     1231233333       Title                       Title                     1231233333       Title                     1231233333       Title                     1231233333       Title                     1231233333       Title                       Title                     1231233333       Title                     1231233333       Title                     1231233333       Title                ",
			"                 1231233333333333333                        1231233333333333333                        1231233333333333333                        1231233333333333333                        1231233333333333333                        1231233333333333333                        1231233333333333333                        1231233333333333333         1231233333333333333                        1231233333333333333                        1231233333333333333                        1231233333333333333                        1231233333333333333         1231233333333333333                        1231233333333333333                        1231233333333333333                        1231233333333333333  ",
			"                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        ",
		})
	end)

	it("should add missing padding before elements", function()
		renderer.set_width(20)

		renderer({
			spacing = 2,
			children = {
				markup.Block({
					markup.Block("inline"),
					markup.Block("inline123"),
					markup.Block("inline"),
					markup.Block("inline"),
				}),
				markup.Block({
					markup.Block("123"),
					markup.Block("123"),
					markup.Block("123"),
					markup.Block("123"),
					markup.Block("123"),
					markup.Block("123"),
				}),
			},
		}, {
			"inline     123      ",
			"inline123  123      ",
			"inline     123      ",
			"inline     123      ",
			"           123      ",
			"           123      ",
		})
	end)

	-- it("should correctly apply missing padding on markup.Text", function()
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
	-- 	}, {
	-- 		"text markup.tree title       ",
	-- 		"      block                   ",
	-- 		"      block                   ",
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
			"12434                         ",
			"  5                           ",
			"  5                           ",
			"  444                         ",
		})
	end)
end)
