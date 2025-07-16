local bit = require("bit")
local Flag = require("markup.core.reconciler.enum").Flag

---@class markup.Fiber.Flags
---@field fiber markup.Fiber
---@field flags integer
local FiberFlags = {}
FiberFlags.__index = FiberFlags

function FiberFlags:new()
	self = setmetatable({}, FiberFlags)
	self.flags = Flag.NONE
	return self
end

---@param ... markup.Fiber.flag
function FiberFlags:set(...)
	self.flags = bit.bor(self.flags, ...) ---@diagnostic disable-line: param-type-mismatch
end

---@param ... markup.Fiber.flag
function FiberFlags:clear(...)
	self.flags = bit.band(self.flags, bit.bnot(bit.bor(...))) ---@diagnostic disable-line: param-type-mismatch
end

---@param ... markup.Fiber.flag
function FiberFlags:check(...)
	return self.flags == ... or bit.band(self.flags, ...) ~= 0 ---@diagnostic disable-line: param-type-mismatch
end

function FiberFlags:reset()
	self.flags = Flag.NONE
end

function FiberFlags:__tostring()
	local flags = {}
	for name, flag in pairs(Flag) do
		if self:check(flag) then
			table.insert(flags, name)
		end
	end
	return "FiberFlags(" .. table.concat(flags, ", ") .. ")"
end

return FiberFlags
