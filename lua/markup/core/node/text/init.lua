local markup = require("markup")
local log = require("markup.logger") ---@diagnostic disable-line: unused-local

---@class markup.Text.props : markup.Node.props
---@field content string

---@class markup.Text : markup.Node
---@field protected _ markup.Text.props
---@field protected super markup.Node
local Text = markup.Node:extend("MarkupText") ---@diagnostic disable-line: undefined-field

---@param content string
function Text:init(content)
    Text.super.init(self, {
        type = "text",
        content = content,
    })
end

---@return string
function Text:content()
    return self._.content
end

---@return integer
function Text:length()
    return vim.fn.strlen(self:content())
end

---@return integer
function Text:width()
    return vim.api.nvim_strwidth(self:content())
end

local CACHE = {}

---@param linenr number line number (1-indexed)
---@param byte_start number start byte position (0-indexed)
---@return nil
function Text:highlight(linenr, byte_start)
    -- if not self._style or vim.tbl_isempty(self._style) then
    --     return
    -- end

    -- local name = self._style
    --
    -- if type(name) == "table" then
    --     ---@cast name table
    --
    --     local parts = {}
    --     for key, value in pairs(self._style) do
    --         table.insert(parts, tostring(key) .. tostring(value))
    --     end
    --     table.sort(parts)
    --     name = ("MARKUP_HL_" .. table.concat(parts, "_")):gsub("[^%w_]", "")
    --
    --     if not CACHE[name] then
    --         vim.api.nvim_set_hl(0, name, self._style)
    --         CACHE[name] = self._style
    --     end
    -- end
    --
    -- vim.api.nvim_buf_set_extmark(bufnr, ns_id, linenr, byte_start, {
    --     end_col = byte_start + self:length(),
    --     hl_group = name,
    --     hl_mode = "combine",
    -- })
end

function Text:render()
    self.parent:_append(self) ---@diagnostic disable-line: invisible
end

---@alias markup.Text.constructor fun(content: string): markup.Text

---@type markup.Text.constructor
local MarkupText = Text ---@diagnostic disable-line: assign-type-mismatch

return MarkupText
