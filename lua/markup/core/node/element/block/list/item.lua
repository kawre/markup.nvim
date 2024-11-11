local markup = require("markup")
local log = require("markup.logger") ---@diagnostic disable-line: unused-local

---@class markup.List.Item : markup.Block
local ListItem = markup.Block:extend("markup.list.item") ---@diagnostic disable-line: undefined-field

-- function ListItem:after_render()
--     ListItem.super.after_render(self)
--
--     local list = self:find_parent(function(node)
--         return node:is_element("list")
--     end)
--
--     local marker = " • "
--     ---@cast list markup.List
--     if list then
--         marker = list:item_marker()
--     end
--
--     for _, line in pairs(self._.lines) do
--         line:prepend(markup.Text(marker))
--     end
-- end

---@alias markup.List.Item.constructor markup.Block.constructor

---@type markup.List.Item.constructor
local MarkupListItem = ListItem ---@diagnostic disable-line: assign-type-mismatch

return MarkupListItem
