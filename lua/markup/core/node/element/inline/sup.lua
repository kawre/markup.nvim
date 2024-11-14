local markup = require("markup")

---@class markup.Inline.Sup : markup.Inline
---@field protected super markup.Inline
local Sup = markup.Element:extend("markup.inline.sup") ---@diagnostic disable-line: undefined-field

function Sup:init(...)
	self:_extend_default_props({
		style = { color = "#9399b3" },
	})
	Sup.super.init(self, ...)
end

function Sup:after_init()
	table.insert(self._.children, 1, markup.Text("^"))
end

---@type markup.Inline.constructor
return Sup
