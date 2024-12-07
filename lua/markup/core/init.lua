local log = require("markup.logger") ---@diagnostic disable-line: unused-local
local enum = require("markup.core.enum")

---@class markup.core
local core = {}

---@type markup.core
return setmetatable(core, {
	__index = function(_, k)
		return enum:lookup(k)
	end,
})
