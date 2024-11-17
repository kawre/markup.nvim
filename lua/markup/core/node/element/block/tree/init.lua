local markup = require("markup")
local log = require("markup.logger")

---@class markup.Block.Tree.props : markup.Block.props
---@field title markup.Node
---@field expand_icons table
---@field expanded boolean

---@class markup.Block.Tree : markup.Block
---@field protected super markup.Block
---@field protected _ markup.Block.Tree.props
local Tree = markup.Block:extend("markup.block.tree") ---@diagnostic disable-line: undefined-field

function Tree:init(...)
	self:_extend_default_props({
		title = markup.Inline("markup.tree title"),
		expand_icons = { " ", " " },
		expanded = false,
	})
	Tree.super.init(self, ...)
end

function Tree:get_title()
	local icon = self._.expanded and self._.expand_icons[2] or self._.expand_icons[1]
	return markup.Inline({ markup.Inline(icon), self._.title })
end

function Tree:_normalize_child_nodes(children)
	local result = {}

	local title = self:get_title()
	if not self._.expanded then
		result = { title }
	else
		result = { title, markup.Block(children) }
	end

	return Tree.super._normalize_child_nodes(self, result)
end

return Tree
