local markup = require("markup.core")

---@class markup.Node.enum : markup.Enum
local enum = markup.Enum()

enum.Type = {
	ELEMENT = "element",
	TEXT = "text",
}

return enum
