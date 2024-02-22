local Element = require("nui.element")

---@class NuiBodyData : NuiBlock.data
---@field pos integer[]

---@class NuiBody : NuiElement
---@field _ NuiBodyData
---@field bufnr integer
---@field winid integer
local Body = Element:extend("NuiBody")

---@param inc? integer
function Body:row(inc)
    local i = self._.pos[1]
    self._.pos = { i + (inc or 0), (inc and 0 or self._.pos[2]) }

    if inc and #vim.api.nvim_buf_get_lines(self.bufnr, 0, -1, false) < i + inc then
        vim.fn.appendbufline(self.bufnr, "$", "")
    end

    return i
end

---@param inc? integer
function Body:col(inc)
    local i = self._.pos[2]
    self._.pos = { self._.pos[1], i + (inc or 0) }
    return i
end

---@param fn function
function Body:modifiable_portal(fn)
    local bufnr = self.bufnr
    if not (bufnr and vim.api.nvim_buf_is_valid(bufnr)) then
        return
    end

    local opts = { buf = bufnr }
    local modi = vim.api.nvim_get_option_value("modifiable", opts)
    if not modi then
        vim.api.nvim_set_option_value("modifiable", true, opts)
    end
    fn()
    if not modi then
        vim.api.nvim_set_option_value("modifiable", false, opts)
    end
end

function Body:draw(data)
    assert(data.bufnr, "bufnr not provided")
    assert(data.winid, "winid not provided")

    self.bufnr = data.bufnr
    self.winid = data.winid
    self._.pos = { 1, 0 }

    local cursor_pos
    if vim.api.nvim_win_is_valid(self.winid) then
        cursor_pos = vim.api.nvim_win_get_cursor(self.winid)
    end
    self:modifiable_portal(function()
        vim.api.nvim_buf_set_lines(self.bufnr, 0, -1, false, {})
        vim.api.nvim_buf_clear_namespace(self.bufnr, -1, 0, -1)
        Body.super.draw(self, self, self)
    end)
    if cursor_pos then
        pcall(vim.api.nvim_win_set_cursor, self.winid, cursor_pos)
    end
end

function Body:init() --
    Body.super.init(self)

    self._.pos = { 1, 0 }
end

local NuiBody = Body

return NuiBody
