local markup = require("markup")
local log = require("markup.logger")

---@class markup.Tree.props : markup.Block.props
---@field title markup.Node
---@field expanded boolean
---@field icons table
---@field indent_size integer

---@class markup.Tree : markup.Block
---@field protected super markup.Block
---@field protected _ markup.Tree.props
local Tree = markup.Flex:extend("markup.block.tree") ---@diagnostic disable-line: undefined-field

function Tree:init(...)
	self:_extend_default_props({
		title = markup.Inline("markup.tree title"),
		expanded = false,
		icons = {
			expand = " ",
			collapse = " ",
			indent = "│",
			indent_last = "└",
			indent_hor = "─",
		},
		indent_size = 2,
	})
	Tree.super.init(self, ...)
end

-- function Tree:after_init()
-- 	table.insert(self._.children, 1, self._.title)
-- end

function Tree:toggle()
	self._.expanded = not self._.expanded
	-- self:reflow()
	self.owner:render()
end

function Tree:get_title()
	local icon = self._.expanded and self._.icons.collapse or self._.icons.expand
	local hl = self._.expanded and "collapse" or "expand"

	return markup.Inline({
		on_submit = function()
			self:toggle()
		end,
		children = {
			markup.Inline(icon, "markup_tree_icon_" .. hl),
			markup.Inline(self._.title, "markup_tree_title"),
		},
	})
end

function Tree:_normalize_child_nodes(children)
	local result = { self:get_title() }

	if self._.expanded then
		for i = 1, #children do
			table.insert(result, children[i])
		end
	end

	return Tree.super._normalize_child_nodes(self, result)
end

function Tree:_periferals_hor_iter()
	local h = self:height()
	local sz = self._.indent_size
	local i = 0

	local indent = self._.icons.indent
	indent = indent .. (" "):rep(sz - vim.fn.strcharlen(indent))

	local indentl = self._.icons.indent_last
	indentl = indentl .. (self._.icons.indent_hor):rep(sz - vim.fn.strcharlen(indentl) - 1) .. " "

	return function()
		if i >= h then
			return
		end

		local icon = indent
		if i == 0 then
			icon = nil
		elseif i == h - 1 then
			icon = indentl
		end

		i = i + 1
		return i - 1, icon, nil
	end
end

---@class markup.Tree.constructor.props : markup.Block.constructor.props
---@field title? markup.Node
---@field icons? table
---@field expanded? boolean
---@field indent_size? integer

---@alias markup.Tree.constructor fun(props?: markup.Tree.constructor.props, style?: markup.Element.style.props): markup.Tree

---@type markup.Tree.constructor
return Tree
