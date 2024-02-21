local Block = require("nui.block")

---@class NuiBodyData : NuiBlockData
---@field line_index integer
---@field bufnr integer
---@field winid integer

---@class NuiBody : NuiBlock
---@field _ NuiBodyData
local Body = Block:extend("NuiBody")

---@param inc? integer
function Body:get_line_idx(inc)
  local index = self._.line_index
  self._.line_index = self._.line_index + (inc or 0)
  return index
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
  self.bufnr = data.bufnr
  self.win_id = data.winid
  local content = self:content()

  self._.line_index = 1

  self:modifiable_portal(function()
    for _, element in ipairs(content) do
      element:draw(self)
    end
  end)
end

function Body:init() --
  Body.super.init(self)

  self._.line_index = 1
end

local NuiBody = Body

return NuiBody