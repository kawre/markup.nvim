local markup = require("markup.core")

---@alias markup.create_root fun(): markup.Element.Table

---@type markup.create_root
local function create_root()
	return markup.create_element("inline")
end

return create_root
