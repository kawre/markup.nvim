local markup = require("markup")
local log = require("markup.logger")

---@class markup.Line.props
---@field highlights { col_start: integer, col_end: integer, hl_group: string }[]
---@field texts markup.Text[]

---@class markup.Line : markup.Object
local Line = markup.Object("MarkupLine")

function Line:init()
    self._ = {
        highlights = {},
        texts = {},
    }
end

function Line:content()
    return table.concat(vim.tbl_map(function(text)
        return text:content()
    end, self._.texts))
end

function Line:length()
    return #self._.chars
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
function Line:append(text)
    table.insert(self._.texts, text)
    return self
end

function Line:get_texts()
    return self._.texts
end

---@alias markup.Line.constructor fun(): markup.Line

---@type markup.Line.constructor
local MarkupLine = Line

return MarkupLine
