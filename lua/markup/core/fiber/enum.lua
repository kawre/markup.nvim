---@alias markup.Fiber.tag
---| "function"
---| "class"
---| "text"
---| "element"
---| "root"
---| "fragment"

---@alias markup.Fiber.type
---| any

local Enum = require("markup.core.create.enum")

---@class markup.fiber.enum : markup.Enum
local enum = Enum()

---@type table<string, markup.Fiber.tag>
enum.Tag = {
	FUNCTION = "function",
	FRAGMENT = "fragment",
	CLASS = "class",
	ROOT = "root",
	TEXT = "text",
	ELEMENT = "element",
}

return enum
