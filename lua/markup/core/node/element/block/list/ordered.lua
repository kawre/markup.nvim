local markup = require("markup")
local log = require("markup.logger") ---@diagnostic disable-line: unused-local

---@class markup.List.Ordered : markup.List
---@field protected super markup.List
local OrderedList = markup.List:extend("markup.list.ordered") ---@diagnostic disable-line: undefined-field

function OrderedList:after_init()
    OrderedList.super.after_init(self)
    self._.ordered = true
end

---@type markup.List
return OrderedList
