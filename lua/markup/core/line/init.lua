local markup = require("markup")
local log = require("markup.logger") ---@diagnostic disable-line
local utils = require("markup.utils") ---@diagnostic disable-line

---@class markup.Line.props
---@field texts markup.Text[]
---@field padding table<"left"|"right", integer>

---@class markup.Line : markup.Object
---@field _ markup.Line.props
local Line = markup.Object("MarkupLine")

function Line:init()
    self._ = {
        texts = {},
        padding = {
            left = 0,
            right = 0,
        },
    }
end

function Line:content()
    local texts = self:texts()

    -- local leftpad, rightpad = self._.padding.left, self._.padding.right
    -- if leftpad > 0 then
    --     table.insert(texts, 1, markup.Padding(leftpad))
    -- end
    -- if rightpad > 0 then
    --     table.insert(texts, markup.Padding(rightpad))
    -- end

    return table.concat(vim.tbl_map(function(text)
        return text:content()
    end, texts))
end

function Line:length()
    return vim.fn.strlen(self:content())
end

function Line:width()
    return vim.api.nvim_strwidth(self:content())
end

---@param renderer markup.Renderer
---@param row_at integer
function Line:draw(renderer, row_at)
    local str = self:content()
    renderer:buf_set_lines(row_at, -1, false, { str })
    self:hightlight(row_at, renderer)
end

function Line:hightlight(row_at, renderer)
    local offset = 0
    for _, text in ipairs(self:texts()) do
        text:highlight(renderer._.bufnr, renderer._.ns_id, row_at, offset)
        offset = offset + text:width()
    end
end

---@param content string|markup.Text|markup.Line
---@param pos? integer
function Line:append(content, pos)
    pos = pos or #self._.texts + 1

    if type(content) == "string" then
        content = markup.Text(content)
    else
        if content._ and content._.texts then -- If content is `markup.Line`
            ---@cast content markup.Line
            for i, text in ipairs(content:texts()) do
                table.insert(self._.texts, pos + (i - 1), text)
            end
        else
            ---@cast content markup.Text
            table.insert(self._.texts, pos, content)
        end
    end

    return self
end

---@param content string|markup.Text|markup.Line
function Line:prepend(content)
    return self:append(content, 1)
end

---@param n integer
function Line:pad_left(n)
    self._.padding.left = self._.padding.left + n
    return self
end

---@param n integer
function Line:pad_right(n)
    self._.padding.right = self._.padding.right + n
    return self
end

---@return markup.Text[]
function Line:texts()
    return self._.texts
end

---@alias markup.Line.constructor fun(): markup.Line

---@type markup.Line.constructor
local MarkupLine = Line ---@diagnostic disable-line

return MarkupLine
