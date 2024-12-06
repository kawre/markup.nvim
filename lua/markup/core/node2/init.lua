local markup = require("markup")

---@class markup.Node2 : markup.Object
---@field type string
---@field props table
---@field children markup.Node2[]
---@field key string
---@field ref string
local Node = markup.Object("markup.node")

function Node:init(type, props, ...)
	--
end

return Node
