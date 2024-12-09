local markup = require("markup.core")

---@class markup.Inline : markup.Element
local Inline = markup.Element:extend("markup.inline")

---@class markup.Inline.static
Inline.static = Inline.static

function Inline.static.layout()
	--
end

return Inline
