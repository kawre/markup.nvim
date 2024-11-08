local markup = require("markup")
local log = require("markup.logger") ---@diagnostic disable-line: unused-local
local u = require("markup.utils") ---@diagnostic disable-line: unused-local

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
    self:hightlight(row_at)
end

function Line:hightlight(row_at)
    local offset = 0
    for _, text in ipairs(self:texts()) do
        text:highlight(row_at, offset)
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

---@return markup.Text[]
function Line:texts()
    return self._.texts
end

---@alias markup.Line.constructor fun(): markup.Line

---@type markup.Line.constructor
local MarkupLine = Line ---@diagnostic disable-line: assign-type-mismatch

return MarkupLine
