local markup = require("markup")

---@class markup.Inline.Sub : markup.Inline
---@field protected super markup.Inline
local Sub = markup.Inline:extend("markup.inline.sub") ---@diagnostic disable-line: undefined-field

function Sub:init(...)
	self:_extend_default_props({
		style = { color = "#9399b3" },
	})
	Sub.super.init(self, ...)
end

function Sub:after_init()
	table.insert(self._.children, 1, markup.Text("_"))
end

---@type markup.Inline.constructor
return Sub
