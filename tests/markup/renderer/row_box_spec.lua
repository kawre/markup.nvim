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

    local function RowBoxRenderer(props, lines)
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

    it("should handle complex spacing", function()
        vim.api.nvim_win_set_width(window.winid, 80)

        RowBoxRenderer({
            align = "center",
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
                        markup.Inline("123123"),
                        markup.Inline("inline"),
                        markup.Inline("inline"),
                        markup.Inline("123123"),
                        markup.Inline("inline"),
                    },
                }),
            },
        }, {
            "                                                                                ",
            "    inline      inline                                                          ",
            "                                                                  123123        ",
            "                              inline           inline             inline        ",
            "                              123123           123123             inline        ",
            "                              inline           inline             123123        ",
            "                              inline           123123             inline        ",
            "                              inline           inline                           ",
            "                              inline           123123                           ",
            "                              inline           inline                           ",
            "                              inline           123123                           ",
            "                              inline           inline                           ",
            "                              inline           123123                           ",
            "                                               inline                           ",
            "                                               123123                           ",
            "                                               inline                           ",
            "                                               123123                           ",
            "                                               inline                           ",
            "                                               123123                           ",
            "                                               inline                           ",
            "                                               123123                           ",
            "                                               inline                           ",
            "                                               123123                           ",
            "                                               inline                           ",
            "                                               123123                           ",
            "                                               inline                           ",
            "                                               123123                           ",
            "                                               inline                           ",
            "                                               123123                           ",
            "                                               inline                           ",
            "                                                                                ",
            "                                                                                ",
            "                                                                                ",
        })
    end)
end)
