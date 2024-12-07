local Enum = require("markup.core.create.enum")

---@class markup.Node.enum : markup.Enum
local enum = Enum()

enum.Type = {
	ELEMENT = "element",
	TEXT = "text",
}

return enum
