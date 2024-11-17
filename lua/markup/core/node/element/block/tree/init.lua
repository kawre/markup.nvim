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
		title = markup.Inline("markup.tree title"),
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
	for i, child in ipairs(self._.children) do
		if child:is_element() then
			local icon = i == #self._.children and self._.icons.indent_last or self._.icons.indent
			child:prepend_child(markup.Extmark({
				virt_text = { { icon } },
			}))
		end
	end
end

function Tree:toggle()
	self._.expanded = not self._.expanded
	-- self:reflow()
	self.owner:render()
end

function Tree:get_title()
	local icon = self._.expanded and self._.expand_icons[2] or self._.expand_icons[1]
	local extmark = markup.Extmark({
		virt_text = { { icon } },
	})
	return markup.Block({
		on_submit = function()
			self:toggle()
		end,
		children = {
			extmark,
			self._.title,
		},
	})
end

function Tree:_normalize_child_nodes(children)
	local result = {}

	local title = self:get_title()
	if not self._.expanded then
		result = { title }
	else
		result = { title, markup.Flex(children) }
	end

	return Tree.super._normalize_child_nodes(self, result)
end

function Tree:after_render()
	Tree.super.after_render(self)
end

---@class markup.Tree.constructor.props : markup.Block.constructor.props
---@field title? markup.Node
---@field expand_icons? table
---@field expanded? boolean

---@alias markup.Tree.constructor fun(props?: markup.Tree.constructor.props, style?: markup.Element.style.props): markup.Tree

---@type markup.Tree.constructor
return Tree
