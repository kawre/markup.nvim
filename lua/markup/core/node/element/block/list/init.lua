local markup = require("markup.core")

---@class markup.List : markup.Block
---@field protected super markup.Block
local List = markup.Block:extend("markup.list")

---@alias markup.List.constructor
---| markup.Block.constructor

---@type markup.List.constructor
return List
