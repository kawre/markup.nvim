---@module 'luassert'

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

	local function RowBoxRenderer(props, lines, extmarks)
		local default = {
			vertical = false,
			children = props,
		}
		if props.children then
			default.children = props.children
		end
		for key, value in pairs(props) do
			default[key] = value
		end
		renderer({
			body = markup.Flex(default),
		}):render()
		h.assert_lines(window, lines)
		if extmarks then
			h.assert_extmarks(window, extmarks)
		end
	end

	it("should render nothing", function()
		RowBoxRenderer({}, {
			"",
		})
	end)

	it("should render inline elements in one row", function()
		RowBoxRenderer({
			markup.Inline("1"),
			markup.Inline("2"),
			markup.Inline("3"),
			markup.Inline("4"),
		}, {
			"1234      ",
		})
	end)

	it("should render block elements in one row", function()
		RowBoxRenderer({
			markup.Block("1"),
			markup.Block("2"),
			markup.Block("3"),
			markup.Block("4"),
		}, {
			"1234      ",
		})
	end)

	it("should render elements in one row", function()
		RowBoxRenderer({
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
		RowBoxRenderer({
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
		RowBoxRenderer({
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
		RowBoxRenderer({
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
		vim.api.nvim_win_set_width(window.winid, 20)

		RowBoxRenderer({
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
		vim.api.nvim_win_set_width(window.winid, 20)

		RowBoxRenderer({
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
		vim.api.nvim_win_set_width(window.winid, 20)

		RowBoxRenderer({
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
		vim.api.nvim_win_set_width(window.winid, 20)

		RowBoxRenderer({
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
		vim.api.nvim_win_set_width(window.winid, 20)

		RowBoxRenderer({
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
		vim.api.nvim_win_set_width(window.winid, 20)

		RowBoxRenderer({
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
		vim.api.nvim_win_set_width(window.winid, 20)

		RowBoxRenderer({
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
		vim.api.nvim_win_set_width(window.winid, 32)

		RowBoxRenderer({
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
		vim.api.nvim_win_set_width(window.winid, 80)

		RowBoxRenderer({
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

	-- it("should handle complex spacing", function()
	--     vim.api.nvim_win_set_width(window.winid, 80)
	--
	--     RowBoxRenderer({
	--         align = "center",
	--         vertical = false,
	--         margin = { 1, 2 },
	--         spacing = 5,
	--         children = {
	--             markup.Inline({
	--                 padding = { 0, 1 },
	--                 children = "inline",
	--             }, { background = "red" }),
	--             markup.Inline("inline"),
	--             markup.Box({
	--                 margin = 1,
	--                 padding = { 1, 2 },
	--                 style = {
	--                     color = "blue",
	--                     background = "white",
	--                 },
	--                 children = {
	--                     markup.Inline("inline"),
	--                     markup.Inline("123123"),
	--                     markup.Inline("inline"),
	--                     markup.Inline("inline"),
	--                     markup.Inline("inline"),
	--                     markup.Inline("inline"),
	--                     markup.Inline("inline"),
	--                     markup.Inline("inline"),
	--                     markup.Inline("inline"),
	--                     markup.Inline("inline"),
	--                 },
	--             }),
	--             markup.Box({
	--                 margin = 1,
	--                 padding = { 1, 2 },
	--                 style = {
	--                     background = "aqua",
	--                     color = "black",
	--                     bold = true,
	--                 },
	--                 children = {
	--                     markup.Inline("inline"),
	--                     markup.Inline("123123"),
	--                     markup.Inline("inline"),
	--                     markup.Inline("123123"),
	--                     markup.Inline("inline"),
	--                     markup.Inline("123123"),
	--                     markup.Inline("inline"),
	--                     markup.Inline("123123"),
	--                     markup.Inline("inline"),
	--                     markup.Inline("123123"),
	--                     markup.Inline("inline"),
	--                     markup.Inline("123123"),
	--                     markup.Inline("inline"),
	--                     markup.Inline("123123"),
	--                     markup.Inline("inline"),
	--                     markup.Inline("123123"),
	--                     markup.Inline("inline"),
	--                     markup.Inline("123123"),
	--                     markup.Inline("inline"),
	--                     markup.Inline("123123"),
	--                     markup.Inline("inline"),
	--                     markup.Inline("123123"),
	--                     markup.Inline("inline"),
	--                     markup.Inline("123123"),
	--                     markup.Inline("inline"),
	--                     markup.Inline("123123"),
	--                     markup.Inline("inline"),
	--                 },
	--             }),
	--             markup.Box({
	--                 margin = 0,
	--                 padding = { 1, 5 },
	--                 style = {
	--                     background = "yellow",
	--                     color = "black",
	--                     bold = true,
	--                 },
	--                 children = {
	--                     markup.Inline("123123"),
	--                     markup.Inline("inline"),
	--                     markup.Inline("inline"),
	--                     markup.Inline("123123"),
	--                     markup.Inline("inline"),
	--                 },
	--             }),
	--         },
	--     }, {
	--         "                                                                                ",
	--         "    inline      inline                                                          ",
	--         "                                                                  123123        ",
	--         "                              inline           inline             inline        ",
	--         "                              123123           123123             inline        ",
	--         "                              inline           inline             123123        ",
	--         "                              inline           123123             inline        ",
	--         "                              inline           inline                           ",
	--         "                              inline           123123                           ",
	--         "                              inline           inline                           ",
	--         "                              inline           123123                           ",
	--         "                              inline           inline                           ",
	--         "                              inline           123123                           ",
	--         "                                               inline                           ",
	--         "                                               123123                           ",
	--         "                                               inline                           ",
	--         "                                               123123                           ",
	--         "                                               inline                           ",
	--         "                                               123123                           ",
	--         "                                               inline                           ",
	--         "                                               123123                           ",
	--         "                                               inline                           ",
	--         "                                               123123                           ",
	--         "                                               inline                           ",
	--         "                                               123123                           ",
	--         "                                               inline                           ",
	--         "                                               123123                           ",
	--         "                                               inline                           ",
	--         "                                               123123                           ",
	--         "                                               inline                           ",
	--         "                                                                                ",
	--         "                                                                                ",
	--         "                                                                                ",
	--     }, {
	--         { 1, 1, 3 },
	--         { 2, 1, 4 },
	--         { 3, 1, 10 },
	--         { 4, 1, 61 },
	--         { 5, 1, 66 },
	--         { 6, 1, 72 },
	--         { 7, 2, 28 },
	--         { 8, 2, 30 },
	--         { 9, 2, 36 },
	--         { 10, 2, 45 },
	--         { 11, 2, 47 },
	--         { 12, 2, 53 },
	--         { 13, 2, 61 },
	--         { 14, 2, 66 },
	--         { 15, 2, 72 },
	--         { 16, 3, 28 },
	--         { 17, 3, 30 },
	--         { 18, 3, 36 },
	--         { 19, 3, 45 },
	--         { 20, 3, 47 },
	--         { 21, 3, 53 },
	--         { 22, 3, 61 },
	--         { 23, 3, 66 },
	--         { 24, 3, 72 },
	--         { 25, 4, 28 },
	--         { 26, 4, 30 },
	--         { 27, 4, 36 },
	--         { 28, 4, 45 },
	--         { 29, 4, 47 },
	--         { 30, 4, 53 },
	--         { 31, 4, 61 },
	--         { 32, 4, 66 },
	--         { 33, 4, 72 },
	--         { 34, 5, 28 },
	--         { 35, 5, 30 },
	--         { 36, 5, 36 },
	--         { 37, 5, 45 },
	--         { 38, 5, 47 },
	--         { 39, 5, 53 },
	--         { 40, 5, 61 },
	--         { 41, 5, 66 },
	--         { 42, 5, 72 },
	--         { 43, 6, 28 },
	--         { 44, 6, 30 },
	--         { 45, 6, 36 },
	--         { 46, 6, 45 },
	--         { 47, 6, 47 },
	--         { 48, 6, 53 },
	--         { 49, 6, 61 },
	--         { 50, 6, 66 },
	--         { 51, 6, 72 },
	--         { 52, 7, 28 },
	--         { 53, 7, 30 },
	--         { 54, 7, 36 },
	--         { 55, 7, 45 },
	--         { 56, 7, 47 },
	--         { 57, 7, 53 },
	--         { 58, 7, 61 },
	--         { 59, 7, 66 },
	--         { 60, 7, 72 },
	--         { 61, 8, 28 },
	--         { 62, 8, 30 },
	--         { 63, 8, 36 },
	--         { 64, 8, 45 },
	--         { 65, 8, 47 },
	--         { 66, 8, 53 },
	--         { 67, 9, 28 },
	--         { 68, 9, 30 },
	--         { 69, 9, 36 },
	--         { 70, 9, 45 },
	--         { 71, 9, 47 },
	--         { 72, 9, 53 },
	--         { 73, 10, 28 },
	--         { 74, 10, 30 },
	--         { 75, 10, 36 },
	--         { 76, 10, 45 },
	--         { 77, 10, 47 },
	--         { 78, 10, 53 },
	--         { 79, 11, 28 },
	--         { 80, 11, 30 },
	--         { 81, 11, 36 },
	--         { 82, 11, 45 },
	--         { 83, 11, 47 },
	--         { 84, 11, 53 },
	--         { 85, 12, 28 },
	--         { 86, 12, 30 },
	--         { 87, 12, 36 },
	--         { 88, 12, 45 },
	--         { 89, 12, 47 },
	--         { 90, 12, 53 },
	--         { 91, 13, 28 },
	--         { 92, 13, 30 },
	--         { 93, 13, 36 },
	--         { 94, 13, 45 },
	--         { 95, 13, 47 },
	--         { 96, 13, 53 },
	--         { 97, 14, 45 },
	--         { 98, 14, 47 },
	--         { 99, 14, 53 },
	--         { 100, 15, 45 },
	--         { 101, 15, 47 },
	--         { 102, 15, 53 },
	--         { 103, 16, 45 },
	--         { 104, 16, 47 },
	--         { 105, 16, 53 },
	--         { 106, 17, 45 },
	--         { 107, 17, 47 },
	--         { 108, 17, 53 },
	--         { 109, 18, 45 },
	--         { 110, 18, 47 },
	--         { 111, 18, 53 },
	--         { 112, 19, 45 },
	--         { 113, 19, 47 },
	--         { 114, 19, 53 },
	--         { 115, 20, 45 },
	--         { 116, 20, 47 },
	--         { 117, 20, 53 },
	--         { 118, 21, 45 },
	--         { 119, 21, 47 },
	--         { 120, 21, 53 },
	--         { 121, 22, 45 },
	--         { 122, 22, 47 },
	--         { 123, 22, 53 },
	--         { 124, 23, 45 },
	--         { 125, 23, 47 },
	--         { 126, 23, 53 },
	--         { 127, 24, 45 },
	--         { 128, 24, 47 },
	--         { 129, 24, 53 },
	--         { 130, 25, 45 },
	--         { 131, 25, 47 },
	--         { 132, 25, 53 },
	--         { 133, 26, 45 },
	--         { 134, 26, 47 },
	--         { 135, 26, 53 },
	--         { 136, 27, 45 },
	--         { 137, 27, 47 },
	--         { 138, 27, 53 },
	--         { 139, 28, 45 },
	--         { 140, 28, 47 },
	--         { 141, 28, 53 },
	--         { 142, 29, 45 },
	--         { 143, 29, 47 },
	--         { 144, 29, 53 },
	--         { 145, 30, 45 },
	--         { 146, 30, 47 },
	--         { 147, 30, 53 },
	--     })
	-- end)

	it("should put highlight at the correct position", function()
		vim.api.nvim_win_set_width(window.winid, 20)

		RowBoxRenderer({
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
end)
