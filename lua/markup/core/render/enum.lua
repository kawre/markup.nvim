local markup = require("markup.core")

---@class markup.Render.enum : markup.Enum
local enum = markup.Enum()

enum.RenderFlow = {
	INLINE = "markup.core.render.layout.inline",
	BLOCK = "markup.core.render.layout.block",
	FLEX = "markup.core.render.layout.flex",
	TEXT = "markup.core.render.layout.text",
}

enum.RenderObject = {
	LAYOUT = "markup.core.render.layout",
	VIEW = "markup.core.render.layout.view",
	enum.RenderFlow,
}

enum.Lookup = {
	TREE = "markup.core.render.tree",
	enum.RenderObject,
}

return enum
