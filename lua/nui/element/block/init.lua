local Element = require("nui.element")

---@class NuiBlock : NuiElement
local Block = Element:extend("ElementBlock")

---@param body NuiBody
function Block:draw(body, ...)
    local lines

    lines = vim.api.nvim_buf_get_lines(body.bufnr, 0, -1, false)
    if lines[body:row()] ~= "" then
        body:row(1)
    end

    Block.super.draw(self, body, ...)

    -- lines = vim.api.nvim_buf_get_lines(body.bufnr, 0, -1, false)
    -- if lines[body:row()] ~= "" then
    --     body:row(1)
    -- end
end

---@type NuiBlock|NuiElement.constructor
local ElementBlock = Block

return ElementBlock
