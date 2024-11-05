local markup = require("markup")
local log = require("markup.logger")

---@class nui_text_extmark
---@field id? integer
---@field hl_group? string
---@field [string] any

---@class markup.Text : markup.Object
---@field protected extmark? nui_text_extmark
---@field protected _content string
---@field protected _length number
---@field protected _width number
---@field protected _style markup.Element.style
---@field type "text"
local Text = markup.Object("MarkupText")

---@param content string|markup.Text
---@param extmark? string|nui_text_extmark highlight group name or extmark options
function Text:init(content, extmark)
    if type(content) == "string" then
        self:set(content, extmark)
    else
        -- cloning
        self:set(content._content, extmark or content.extmark)
    end
    self._style = {}
    self.type = "text"
end

---@param content string text content
---@param extmark? string|nui_text_extmark highlight group name or extmark options
---@return markup.Text
function Text:set(content, extmark)
    if self._content ~= content then
        self._content = content
        self._length = vim.fn.strlen(content)
        self._width = vim.api.nvim_strwidth(content)
    end

    if extmark then
        -- preserve self.extmark.id
        local id = self.extmark and self.extmark.id or nil
        self.extmark = type(extmark) == "string" and { hl_group = extmark } or vim.deepcopy(extmark)
        self.extmark.id = id
    end

    return self
end

---@return string
function Text:content()
    return self._content
end

---@return number
function Text:length()
    return self._length
end

---@return number
function Text:width()
    return self._width
end

local CACHE = {}

---@param bufnr number buffer number
---@param ns_id number namespace id
---@param linenr number line number (1-indexed)
---@param byte_start number start byte position (0-indexed)
---@return nil
function Text:highlight(bufnr, ns_id, linenr, byte_start)
    if not self._style or vim.tbl_isempty(self._style) then
        return
    end

    local name = self._style

    if type(name) == "table" then
        ---@cast name table

        local parts = {}
        for key, value in pairs(self._style) do
            table.insert(parts, tostring(key) .. tostring(value))
        end
        table.sort(parts)
        name = ("MARKUP_HL_" .. table.concat(parts, "_")):gsub("[^%w_]", "")

        if not CACHE[name] then
            vim.api.nvim_set_hl(0, name, self._style)
            CACHE[name] = self._style
        end
    end

    vim.api.nvim_buf_set_extmark(bufnr, ns_id, linenr, byte_start, {
        end_col = byte_start + self:length(),
        hl_group = name,
        hl_mode = "combine",
    })
end

---@param renderer markup.Renderer
---@param parent markup.Element
function Text:build(renderer, parent)
    local state = renderer:state(parent)
    self._style = state.style
    state:append(self)
end

---@alias markup.Text.constructor fun(content: string|markup.Text, extmark?: string|nui_text_extmark): markup.Text

---@type markup.Text.constructor
local MarkupText = Text ---@diagnostic disable-line

return MarkupText
