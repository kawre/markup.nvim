local markup = require("markup.core")

local u = require("markup.utils") ---@diagnostic disable-line: unused-local
local log = require("markup.logger") ---@diagnostic disable-line: unused-local

---@class markup.Renderer.props : markup.Window.props
---@field body markup.Element.children
---@field buttons markup.Element[]

---@class markup.Renderer : markup.Window
---@field protected super markup.Window
---@field protected _ markup.Renderer.props
---@field reconciler markup.Reconciler
---@field render_tree markup.Render.Tree
---@field root markup.Renderer.Root
local Renderer = markup.Window:extend("MarkupRenderer") ---@diagnostic disable-line: undefined-field

---------------------------------
---- Methods
---------------------------------

function Renderer:after_init()
	Renderer.super.after_init(self)
	self.body = self._.body
end

---@param element markup.xElement | markup.xElement[]
function Renderer:render(element)
	self.root = markup.create_renderer_root(self, element)
	self.reconciler = markup.Reconciler(self)
	self.reconciler:reconcile()
	self.reconciler:print()
	self.render_tree = markup.Render.Tree(self.root)
	self.root.current.state_node:print()
	self:commit()
end

function Renderer:rerender()
	self.reconciler:reconcile()
	self.render_tree = markup.Render.Tree(self.root)
	self:commit()
end

---@param node markup.Node
function Renderer:add_btn(node)
	local nd = node or {}
	local children = nd.child_nodes or {}

	for _, child in ipairs(children) do
		self:add_btn(child)
	end

	if nd and nd.props and nd.props.on_submit then
		vim.keymap.set("n", "b", function()
			nd.props.on_submit()
		end)
	end
end

---@private
function Renderer:commit()
	self:render_portal(function()
		self.render_tree.view:paint(self)
	end)

	self:add_btn(self.root.current.state_node)
end

---@param fn fun()
function Renderer:render_portal(fn)
	assert(self:is_valid(), "Renderer is not valid")

	self:preserve_cursor(function()
		self:with_buf_option("modifiable", function()
			self:clear()
			fn()
		end)
	end)

	return true
end

---@param line_start? integer
---@param line_end? integer
function Renderer:buf_clear_namespace(line_start, line_end)
	Renderer.super.buf_clear_namespace(self, self._.ns_id, line_start, line_end)
end

function Renderer:clear()
	self:buf_clear_namespace()
	self:clear_keymaps()
end

function Renderer:preserve_cursor(fn)
	local c = vim.api.nvim_win_get_cursor(self.winid)
	fn()
	pcall(vim.api.nvim_win_set_cursor, self.winid, c)
end

function Renderer:add_button(button)
	table.insert(self._.buttons, button)
end

function Renderer:handle_on_submit()
	local c = vim.api.nvim_win_get_cursor(self.winid)

	for _, btn in ipairs(self._.buttons or {}) do
		if btn:_in_range(c) then
			btn:event("submit")
			return
		end
	end
end

---------------------------------
---- Setters
---------------------------------

-- ---@param body markup.Element.children
-- function Renderer:set_body(body)
-- 	self._.body = body
-- end
--
-- ---------------------------------
-- ---- Getters
-- ---------------------------------
--
-- function Renderer:body()
-- 	return self._.body or ""
-- end

---------------------------------
---- Initializer
---------------------------------

---@class markup.Renderer.constructor.props : markup.Window.constructor.props
---@field body? markup.Element.children

---@alias markup.Renderer.constructor fun(props?: markup.Renderer.constructor.props): markup.Renderer

---@type markup.Renderer.constructor
local MarkupRenderer = Renderer ---@diagnostic disable-line: assign-type-mismatch

return MarkupRenderer
