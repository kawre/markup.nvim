local markup = require("markup")
local log = require("markup.logger")

---@class markup.Tree.props : markup.Block.props
---@field title markup.Node
---@field expanded boolean
---@field icons markup.Tree.icons
---@field indent_size integer

---@class markup.Tree : markup.Block
---@field protected super markup.Block
---@field protected _ markup.Tree.props
local Tree = markup.Block:extend("markup.block.tree") ---@diagnostic disable-line: undefined-field

function Tree:init(...)
	self:_extend_default_props({
		expanded = false,
		title = "Tree", -- stackoverflow when title is a markup.Node
		icons = {
			expand = "",
			collapse = "",
			indent = "│",
			indent_last = "└",
			indent_hor = "─",
			-- indent = " ",
			-- indent_last = " ",
			-- indent_hor = " ",
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
	local icon = (self._.expanded and self._.icons.collapse or self._.icons.expand) .. " "
	local hl = "MarkupTreeIcon" .. (self._.expanded and "Collapse" or "Expand")

	return markup.Block({
		on_submit = function()
			self:toggle()
		end,
		children = {
			markup.Inline(icon, hl),
			markup.Inline(self._.title, "MarkupTreeTitle"),
		},
	}, { bg = "red" })
end

function Tree:_normalize_child_nodes(children)
	local result = { self:get_title() }

	if self._.expanded then
		vim.list_extend(result, children)
	end

	return Tree.super._normalize_child_nodes(self, result)
end

function Tree:_peripherals_hor_iter()
	local h = self:height()
	local sz = self._.indent_size
	local i = 0

	local indent = self._.icons.indent
	indent = indent .. (" "):rep(sz - vim.fn.strcharlen(indent))

	local indentl = self._.icons.indent_last
	indentl = indentl .. (self._.icons.indent_hor):rep(sz - vim.fn.strcharlen(indentl) - 1) .. " "

	local mock = self:mock_element("MarkupTreeIndent")

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
		return i - 1, icon and markup.Text(icon, mock), nil
	end
end

---@class markup.Tree.constructor.props : markup.Block.constructor.props
---@field title? markup.Element.children
---@field icons? markup.Tree.icons.props
---@field expanded? boolean
---@field indent_size? integer

---@alias markup.Tree.constructor fun(props?: markup.Tree.constructor.props, style?: markup.Element.style.props): markup.Tree

---@type markup.Tree.constructor
return Tree
