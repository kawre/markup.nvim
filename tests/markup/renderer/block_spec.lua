---@module 'luassert'

local markup = require("markup")
local h = require("tests.helpers")

describe("Block Renderer", function()
    ---@type table, markup.Renderer
    local window, renderer

    before_each(function()
        window = h.open_window()
        renderer = h.bind_renderer(window)
    end)

    after_each(function()
        h.close_window(window)
    end)

    local function BlockRenderer(children, lines)
        renderer({
            body = markup.Block({
                children = children,
            }),
        }):render()

        h.assert_lines(window, lines)
    end

    it("should render nothing", function()
        BlockRenderer({}, {
            "",
        })
    end)

    it("should render inline elements in one row", function()
        BlockRenderer({
            markup.Inline("1"),
            markup.Inline("2"),
            markup.Inline("3"),
            markup.Inline("4"),
        }, {
            "1234",
        })
    end)

    it("should render block elements one per row", function()
        BlockRenderer({
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
        BlockRenderer({
            markup.Inline("1"),
            markup.Block("2"),
        }, {
            "1",
            "2",
        })
    end)

    it("should render elements acording to their type", function()
        BlockRenderer({
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
end)
