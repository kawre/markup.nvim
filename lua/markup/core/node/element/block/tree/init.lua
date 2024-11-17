local markup = require("markup")
local log = require("markup.logger")

---@class markup.Tree.props : markup.Block.props
---@field title markup.Node
---@field expand_icons table
---@field expanded boolean

---@class markup.Tree : markup.Block
---@field protected super markup.Block
---@field protected _ markup.Tree.props
local Tree = markup.Block:extend("markup.block.tree") ---@diagnostic disable-line: undefined-field

function Tree:init(...)
	self:_extend_default_props({
		title = markup.Inline({
			on_submit = function()
				self:toggle()
			end,
			children = "Title",
		}),
		expand_icons = { " ", " " },
		expanded = false,
		icons = {
			expand = " ",
			collapse = " ",
			indent = "│ ",
			indent_last = "└ ",
		},
	})
	Tree.super.init(self, ...)
end

function Tree:after_init()
	table.insert(self._.children, 1, self._.title)
end

function Tree:toggle()
	self._.expanded = not self._.expanded
	-- self:reflow()
	self.owner:render()
end

function Tree:_normalize_child_nodes(children)
	local result = { children[1] }

	if self._.expanded then
		for i = 2, #children do
			table.insert(result, children[i])
		end
	end

	return Tree.super._normalize_child_nodes(self, result)
end

function Tree:_periferals_hor_iter()
	local h = self:height()
	local i = 0

	return function()
		if i < h then
			local icon = self._.icons.indent

			if i == 0 then
				icon = self._.expanded and self._.expand_icons[2] or self._.expand_icons[1]
			elseif i == h - 1 then
				icon = self._.icons.indent_last
			end
			i = i + 1
			return i - 1, icon, nil
		end
	end
end

function Tree:_apply_periferals()
	if not self:is_block_kind() then
		return
	end

	for row, left, right in self:_periferals_hor_iter() do
		if left then
			self:_line(row):prepend(left)
		end
		if right then
			self:_line(row):append(right)
		end
	end
end

---@class markup.Tree.constructor.props : markup.Block.constructor.props
---@field title? markup.Node
---@field expand_icons? table
---@field expanded? boolean

---@alias markup.Tree.constructor fun(props?: markup.Tree.constructor.props, style?: markup.Element.style.props): markup.Tree

---@type markup.Tree.constructor
return Tree
