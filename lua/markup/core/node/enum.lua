local Enum = require("markup.collections.enum")

---@class markup.Node.enum : markup.Enum
local enum = Enum()

enum.Type = {
	ELEMENT = "element",
	TEXT = "text",
}

return enum
