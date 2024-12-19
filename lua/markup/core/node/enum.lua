local markup = require("markup.core")

---@class markup.Node.enum : markup.Enum
local enum = markup.Enum()

---@enum markup.Node.type
enum.Type = {
	ELEMENT = "element",
	TEXT = "text",
}

enum.Display = {
	NONE = "none",
	BLOCK = "block",
	INLINE = "inline",
	FLEX = "flex",
}

return enum
