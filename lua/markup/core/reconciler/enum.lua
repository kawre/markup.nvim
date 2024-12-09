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
	UPDATE = 1,
	INSERT = 2,
	DELETE = 3,
	PLACEMENT = 4,
}

return enum
