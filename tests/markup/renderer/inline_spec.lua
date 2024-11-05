---@module 'luassert'

local markup = require("markup")
local h = require("tests.helpers")

describe("Inline Renderer", function()
    ---@type table, markup.Renderer
    local window, renderer

    before_each(function()
        window = h.open_window()
        renderer = h.bind_renderer(window)
    end)

    after_each(function()
        h.close_window(window)
    end)

    local function InlineRenderer(children, lines)
        renderer({
            body = markup.Inline({
                children = children,
            }),
        }):render()

        h.assert_lines(window, lines)
    end

    it("should render nothing", function()
        InlineRenderer({}, {
            "",
        })
    end)

    it("should render inline elements in one row", function()
        InlineRenderer({
            markup.Inline("1"),
            markup.Inline("2"),
            markup.Inline("3"),
            markup.Inline("4"),
        }, {
            "1234",
        })
    end)

    it("should render block elements one per row", function()
        InlineRenderer({
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
        InlineRenderer({
            markup.Inline("1"),
            markup.Block("2"),
        }, {
            "1",
            "2",
        })
    end)

    it("should render elements acording to their type", function()
        InlineRenderer({
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
