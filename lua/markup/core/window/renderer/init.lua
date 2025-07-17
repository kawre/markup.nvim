local markup = require("markup.core")

local u = require("markup.utils") ---@diagnostic disable-line: unused-local
local log = require("markup.logger") ---@diagnostic disable-line: unused-local
local RenderNodeFactory = require("markup.core.factory.render-node")
local RenderTree = require("markup.core.render.tree")
local RendererFactory = require("markup.core.factory.renderer")
local DevToolsFiberTreePicker = require("markup.dev-tools.picker.fiber-tree")
local DevToolsNodeTreePicker = require("markup.dev-tools.picker.node-tree")
local DevToolsRenderTreePicker = require("markup.dev-tools.picker.render-tree")

---@class markup.Renderer.meta.render
---@field node_root markup.Node
---@field fiber_root markup.Fiber
---@field render_root markup.Render.Node
---@field index integer

---@class markup.Renderer.meta
---@field render_count integer
---@field renders markup.Renderer.meta.render[]

---@class markup.Renderer.props : markup.Window.props
---@field body markup.Element.children
---@field buttons markup.Element[]

---@class markup.Renderer : markup.Window
---@field protected super markup.Window
---@field protected _ markup.Renderer.props
---@field reconciler markup.Reconciler
---@field render_tree markup.Render.Tree
---@field root markup.Renderer.Root
---@field _meta markup.Renderer.meta
local Renderer = markup.Window:extend("MarkupRenderer") ---@diagnostic disable-line: undefined-field

---------------------------------
---- Methods
---------------------------------

function Renderer:after_init()
	Renderer.super.after_init(self)
	self.body = self._.body
	self._meta = { render_count = 0, renders = {} }
	self.ns = vim.api.nvim_create_namespace("renderer")
	table.insert(_Markup.renderers, self)
end

---@param element markup.Element|markup.Element[]
function Renderer:render(element)
	self._meta = { render_count = 0, renders = {} }

	self.root = RendererFactory.create_root(self, element)
	self.reconciler = markup.Reconciler()
	self.render_tree = RenderTree:new(self)

	self:rerender()
end

function Renderer:rerender()
	vim.api.nvim_buf_clear_namespace(self.bufnr, self.ns, 0, -1)
	_MTEMP = {}
	self.reconciler:reconcile(self.root)
	self.render_tree:build()
	self.render_tree:layout()
	self.render_tree:paint()
end

function Renderer:_render_()
	-- vim.api.nvim_buf_clear_namespace(self.bufnr, ns, 0, -1)
	-- self:_render_node_tree(self.bufnr)
	-- self:_render_render_tree(self.sbuf)
end

function Renderer:_render_picker(items, bufnr)
	local lines = vim.tbl_map(function(i)
		return i.item.entry
	end, items)

	local width = self.render_tree.width
	local height = self.render_tree.height
	local _lines = {}
	local _line = (" "):rep(width)
	for i = 1, math.max(height, #lines) do
		_lines[i] = _line
	end
	vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, _lines)

	for i, line in ipairs(lines) do
		local x = 0
		for _, chunk in ipairs(line) do
			vim.api.nvim_buf_set_extmark(bufnr, self.ns, i - 1, x, {
				virt_text = { chunk },
				virt_text_pos = "overlay",
			})
			x = x + vim.api.nvim_strwidth(chunk[1])
		end
	end
end

function Renderer:_render_fiber_tree(bufnr)
	local items = DevToolsFiberTreePicker(self.root.current)
	self:_render_picker(items, bufnr)
end

function Renderer:_render_render_tree(bufnr)
	local items = DevToolsRenderTreePicker(self.root.current.state_node.render_box)
	self:_render_picker(items, bufnr)
end

function Renderer:_render_node_tree(bufnr)
	local items = DevToolsNodeTreePicker(self.root.current.state_node)
	self:_render_picker(items, bufnr)
end

function Renderer:update_meta()
	self._meta.render_count = self._meta.render_count + 1
	---@type markup.Renderer.meta.render
	local render_meta = {
		fiber_root = self.root.current,
		node_root = self.root.current.state_node,
		render_root = self.render_tree,
		index = self._meta.render_count,
	}
	render_meta = vim.tbl_map(vim.deepcopy, render_meta)
	table.insert(self._meta.renders, render_meta)
end

---@param node markup.Node
function Renderer:add_button(node)
	if not self._.buttons then
		self._.buttons = {}
	end

	table.insert(self._.buttons, node)
end

function Renderer:add_keymap(key, event)
	if not self._.keymaps.pending then
		self._.keymaps.pending = {}
	end

	self._.keymaps.pending[key] = { mode = "n", callback = event }
end

---@private
function Renderer:commit()
	self:render_portal(function()
		self.render_tree.view:paint(self)
	end)

	self:commit_keymaps()
end

function Renderer:commit_keymaps()
	if not self._.keymaps.pending then
		return
	end

	for key, map in pairs(self._.keymaps.pending) do
		self.buf:set_keymap(map.mode, key, "", {
			callback = map.callback,
		})
	end
	self._.keymaps.active = self._.keymaps.pending
	self._.keymaps.pending = nil
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

function Renderer:clear()
	self.buf:clear_namespace(self.ns, 0, -1)
	self:clear_keymaps()
	self._.buttons = nil
end

function Renderer:preserve_cursor(fn)
	local c = self.win:get_cursor()
	fn()
	pcall(vim.api.nvim_win_set_cursor, self.id, c)
end

function Renderer:handle_on_submit()
	local c = self.win:get_cursor()

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
