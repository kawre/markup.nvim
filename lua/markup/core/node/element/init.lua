local log = require("markup.logger") ---@diagnostic disable-line: unused-local
local NodeType = require("markup.core.node.enum").Type
local markup = require("markup.core")

---@class markup.Element : markup.Node
local Element = markup.Node:extend("markup.element")

function Element:init(props)
	assert(self.class.super, "Element is an abstract class")

	Element.super.init(self, NodeType.ELEMENT)
	self.props = props
end

return Element
