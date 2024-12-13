local markup = require("markup.core")

---@class markup.Fiber.enum : markup.Enum
local enum = markup.Enum()

---@alias markup.Fiber.type
---| any

---@enum markup.Fiber.tag
enum.Tag = {
	FUNCTION = "function",
	FRAGMENT = "fragment",
	CLASS = "class",
	ROOT = "root",
	TEXT = "text",
	ELEMENT = "element",
}

---@enum markup.Fiber.flag
enum.Flag = {
	NONE = 0,
	UPDATE = 1,
	INSERT = 2,
	DELETE = 4,
	PLACEMENT = 8,
	-- PERFORMED_WORK = 5,

	---@param fiber markup.Fiber
	---@param ... markup.Fiber.flag
	set = function(fiber, ...)
		fiber.flags = bit.bor(fiber.flags, ...) ---@diagnostic disable-line: param-type-mismatch
	end,

	---@param fiber markup.Fiber
	---@param ... markup.Fiber.flag
	clear = function(fiber, ...)
		fiber.flags = bit.band(fiber.flags, bit.bnot(bit.bor(...))) ---@diagnostic disable-line: param-type-mismatch
	end,

	---@param fiber markup.Fiber
	---@param ... markup.Fiber.flag
	check = function(fiber, ...)
		return bit.band(fiber.flags, ...) ~= 0 ---@diagnostic disable-line: param-type-mismatch
	end,
}

return enum
