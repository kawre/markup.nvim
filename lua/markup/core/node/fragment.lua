local markup = require("markup")

---@class markup.Fragment : markup.Node
---@field protected super markup.Node
---@field _child_nodes markup.Node[]
local Fragment = markup.Node:extend("markup.fragment") ---@diagnostic disable-line: undefined-field

function Fragment:init(children)
	Fragment.super.init(self, {
		type = "fragment",
	})

	---@diagnostic disable-next-line: undefined-field
	self._child_nodes = markup.Element.static._normalize_children(children)
end

function Fragment:unpack(tbl)
	for _, node in ipairs(self._child_nodes) do
		if node:is_type("fragment") then
			---@cast node markup.Fragment
			node:unpack(tbl)
		else
			table.insert(tbl, node)
		end
	end
end

---@alias markup.Fragment.constructor fun(children?: markup.Element.children): markup.Fragment

---@type markup.Fragment.constructor
return Fragment
