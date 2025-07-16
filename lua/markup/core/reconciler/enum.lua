local markup = require("markup.core")
local u = require("markup.utils")

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

	-- indicates that the Fiber's associated node
	-- needs to be inserted into the render tree
	PLACEMENT = 1,

	-- signals that the properties, state, or children of the Fiber node
	-- have changed and need to be updated
	UPDATE = 2,

	-- indicates that the Fiber's associated node
	-- should be removed from the render tree
	DELETE = 4,

	CHILD_DELETE = 16,
}

return enum
