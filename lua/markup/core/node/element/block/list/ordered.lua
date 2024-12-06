local markup = require("markup.core")
local log = require("markup.logger") ---@diagnostic disable-line: unused-local

---@class markup.List.Ordered : markup.List
---@field protected super markup.List
local OrderedList = markup.List:extend("markup.list.ordered") ---@diagnostic disable-line: undefined-field

function OrderedList:init(...)
	self:extend_default_props({
		ordered = true,
	})
	OrderedList.super.init(self, ...)
end

---@type markup.List
return OrderedList
