---@alias markup.Fiber.type
---| any

local Enum = require("markup.core.create.enum")

---@class markup.fiber.enum : markup.Enum
local enum = Enum()

---@alias markup.Fiber.tag
---| "function"
---| "class"
---| "text"
---| "element"
---| "root"
---| "fragment"
---| "indeterminate"

---@type table<string, markup.Fiber.tag>
enum.Tag = {
	FUNCTION = "function",
	FRAGMENT = "fragment",
	CLASS = "class",
	ROOT = "root",
	TEXT = "text",
	ELEMENT = "element",
	INDETERMINATE = "indeterminate",
}

---@alias markup.Fiber.flag
---| 1
---| 2
---| 3

---@type table<string, markup.Fiber.flag>
enum.Flag = {
	UPDATE = 1,
	INSERT = 2,
	DELETE = 3,
}

return enum
