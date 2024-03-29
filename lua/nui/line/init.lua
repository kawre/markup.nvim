local Object = require("nui.object")
local NuiText = require("nui.text")
local defaults = require("nui.utils").defaults

---@class NuiLine
---@field _texts NuiText[]
local Line = Object("NuiLine")

---@param texts? NuiText[]
function Line:init(texts)
    self._texts = defaults(texts, {})
end

---@param content string|NuiText|NuiLine
---@param highlight? string|nui_text_extmark data for highlight
---@return NuiText|NuiLine
function Line:append(content, highlight)
    local block = content
    if type(block) == "string" then
        block = NuiText(block, highlight)
    end
    if block._texts then
        ---@cast block NuiLine
        for _, text in ipairs(block._texts) do
            table.insert(self._texts, text)
        end
    else
        ---@cast block NuiText
        table.insert(self._texts, block)
    end
    return block
end

---@return string
function Line:content()
    return table.concat(vim.tbl_map(function(text)
        return text:content()
    end, self._texts))
end

---@return number
function Line:width()
    local width = 0
    for _, text in ipairs(self._texts) do
        width = width + text:width()
    end
    return width
end

---@param bufnr number buffer number
---@param ns_id number namespace id
---@param linenr number line number (1-indexed)
---@param ___byte_start___? integer start byte position (0-indexed)
---@return nil
function Line:highlight(bufnr, ns_id, linenr, ___byte_start___)
    local current_byte_start = ___byte_start___ or 0
    for _, text in ipairs(self._texts) do
        text:highlight(bufnr, ns_id, linenr, current_byte_start)
        current_byte_start = current_byte_start + text:length()
    end
end

---@param bufnr number buffer number
---@param ns_id number namespace id
---@param linenr_start number start line number (1-indexed)
---@param linenr_end? number end line number (1-indexed)
---@return nil
function Line:render(bufnr, ns_id, linenr_start, linenr_end)
    local row_start = linenr_start - 1
    local row_end = linenr_end and linenr_end - 1 or row_start + 1
    local content = self:content()
    vim.api.nvim_buf_set_lines(bufnr, row_start, row_end, false, { content })
    self:highlight(bufnr, ns_id, linenr_start)
end

function Line:draw(body, parent)
    for _, element in ipairs(self._texts) do
        element:draw(body, self)
    end
end

---@alias NuiLine.constructor fun(texts?: NuiText[]): NuiLine
---@type NuiLine|NuiLine.constructor
local NuiLine = Line

return NuiLine
