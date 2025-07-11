local normalizer = require("markup.core.node.normalizer")
local Node = require("markup.core.node")

---@class markup.factory.Node
local M = {}

---@param element markup.xElement
function M.create(element)
	local props = normalizer.props(element.props, element._style)
	return Node:new(element.type, props)
end

return M
