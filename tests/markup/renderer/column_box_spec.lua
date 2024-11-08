---@module 'luassert'

local markup = require("markup")
local h = require("tests.helpers")

describe("ColumnBox Renderer", function()
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
            vertical = true,
            children = props,
        }
        if props.children then
            default.children = props.children
        end
        for key, value in pairs(props) do
            default[key] = value
        end
        renderer({
            body = markup.Box(default),
        }):render()
        h.assert_lines(window, lines)
    end

    it("should render nothing", function()
        ColumnBoxRenderer({}, {
            "",
        })
    end)

    it("should render inline elements one per row", function()
        ColumnBoxRenderer({
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
        ColumnBoxRenderer({
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
        ColumnBoxRenderer({
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
            "1         ",
            "2         ",
            "33        ",
            "4         ",
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
            "1         ",
            "2         ",
            "3 3       ",
            "4         ",
        })
    end)

    it("should align elements to the start", function()
        ColumnBoxRenderer({
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
        ColumnBoxRenderer({
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
        ColumnBoxRenderer({
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
        ColumnBoxRenderer({
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
        ColumnBoxRenderer({
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
        ColumnBoxRenderer({
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
        vim.api.nvim_win_set_width(window.winid, 26)

        ColumnBoxRenderer({
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
                            direction = "row",
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
        vim.api.nvim_win_set_width(window.winid, 26)

        ColumnBoxRenderer({
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
                            direction = "row",
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
        vim.api.nvim_win_set_width(window.winid, 30)

        ColumnBoxRenderer({
            align = "center",
            spacing = 2,
            children = {
                markup.Inline("Top"),
                markup.Box({
                    align = "start",
                    direction = "column",
                    children = {
                        markup.Inline("Start Box"),
                        markup.Box({
                            align = "end",
                            direction = "row",
                            children = {
                                markup.Inline("End Row 1"),
                                markup.Block("End Row 2"),
                            },
                        }),
                        markup.Box({
                            align = "center",
                            direction = "column",
                            spacing = 1,
                            children = {
                                markup.Inline("Center Column 1"),
                                markup.Box({
                                    align = "start",
                                    direction = "row",
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
        vim.api.nvim_win_set_width(window.winid, 30)

        ColumnBoxRenderer({
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
end)
