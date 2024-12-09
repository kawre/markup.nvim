local markup = require("markup.core")

---@class markup.Pre : markup.Block
---@field protected super markup.Block
local Pre = markup.Block:extend("markup.pre")

---@alias markup.Pre.constructor
---| markup.Block.constructor

---@type markup.Pre.constructor
return Pre
