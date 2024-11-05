local markup = require("markup")
local log = require("markup.logger") ---@diagnostic disable-line

---@class markup.Line.props
---@field texts markup.Text[]
---@field padding table<"left"|"right", integer>

---@class markup.Line : markup.Object
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

    local leftpad, rightpad = self._.padding.left, self._.padding.right
    if leftpad > 0 then
        table.insert(texts, 1, markup.Padding(leftpad))
    end
    if rightpad > 0 then
        table.insert(texts, markup.Padding(rightpad))
    end

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

function Line:draw(renderer, row_at)
    local str = self:content()
    vim.api.nvim_buf_set_lines(renderer._.bufnr, row_at, -1, true, { str })

    -- local offset = 0
    -- for _, text in ipairs(self._.highlights) do
    -- text:highlight(renderer._.bufnr, renderer._.ns_id, row_at, offset)
    -- offset = offset + text:width()
    -- end
end

---@param text markup.Text
---@param pos? integer
function Line:append(text, pos)
    if pos then
        table.insert(self._.texts, pos, text)
    else
        table.insert(self._.texts, text)
    end
    return self
end

---@param text markup.Text
function Line:prepend(text)
    return self:append(text, 1)
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

function Line:texts()
    return self._.texts
end

---@alias markup.Line.constructor fun(): markup.Line

---@type markup.Line.constructor
local MarkupLine = Line ---@diagnostic disable-line

return MarkupLine
