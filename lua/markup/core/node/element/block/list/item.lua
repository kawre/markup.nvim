local markup = require("markup.core")

---@class markup.List.Item : markup.Block
---@field protected super markup.Block
local ListItem = markup.Block:extend("markup.list.item")

---@alias markup.List.Item.constructor
---| markup.Block.constructor

---@type markup.List.Item.constructor
return ListItem
