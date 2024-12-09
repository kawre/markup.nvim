local markup = require("markup.core")

---@class markup.List.Ordered : markup.List
---@field protected super markup.List
local OrderedList = markup.List:extend("markup.list.ordered")

---@alias markup.List.Ordered.constructor
---| markup.List.constructor

---@type markup.List.Ordered.constructor
return OrderedList
