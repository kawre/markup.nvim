local markup = require("markup.core")

---@class markup.Render.enum : markup.Enum
local enum = markup.Enum()

enum.RenderFlow = {
	INLINE = "markup.core.render.object.inline",
	BLOCK = "markup.core.render.object.block",
	FLEX = "markup.core.render.object.flex",
	TEXT = "markup.core.render.object.text",
}

enum.RenderObject = {
	OBJECT = "markup.core.render.object",
	VIEW = "markup.core.render.object.view",
	enum.RenderFlow,
}

enum.Lookup = {
	TREE = "markup.core.render.tree",
	enum.RenderObject,
}

return enum
