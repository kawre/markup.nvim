local markup = require("markup.core")

local u = require("markup.utils") ---@diagnostic disable-line: unused-local
local log = require("markup.logger") ---@diagnostic disable-line: unused-local
local RenderNodeFactory = require("markup.core.factory.render-node")
local RendererFactory = require("markup.core.factory.renderer")
local DevToolsFiberTreePicker = require("markup.dev-tools.picker.fiber-tree")
local DevToolsNodeTreePicker = require("markup.dev-tools.picker.node-tree")
local DevToolsRenderTreePicker = require("markup.dev-tools.picker.render-tree")

_XDDD = {}

---@class markup.Renderer.props : markup.Window.props
---@field body markup.Element.children
---@field buttons markup.Element[]

---@class markup.Renderer : markup.Window
---@field protected super markup.Window
---@field protected _ markup.Renderer.props
---@field reconciler markup.Reconciler
---@field render_tree markup.Render.Node
---@field root markup.Renderer.Root
local Renderer = markup.Window:extend("MarkupRenderer") ---@diagnostic disable-line: undefined-field

---------------------------------
---- Methods
---------------------------------

function Renderer:after_init()
	Renderer.super.after_init(self)
	self.body = self._.body
end

local ns = vim.api.nvim_create_namespace("markup_renderer")

---@param element markup.Element|markup.Element[]
function Renderer:render(element)
	_XDDD = {}
	-- if vim.in_fast_event() then
	-- 	return vim.schedule(function()
	-- 		self:render(element)
	-- 	end)
	-- end
	vim.api.nvim_buf_clear_namespace(self.bufnr, ns, 0, -1)

	u.measure_time("--- render", function()
		self.root = RendererFactory.create_root(self, element)
		self.reconciler = markup.Reconciler(self)
		self.reconciler:reconcile()
		-- DevToolsFiberTreePicker(self.root.current)
		-- DevToolsNodeTreePicker(self.root.current.state_node)
		-- self.render_tree = RenderNodeFactory.create_root(self)
		-- self.render_tree:build()
		-- for _, child in ipairs(self.render_tree.children) do
		-- 	child:layout()
		-- end
		--
		-- local xd = {}
		-- local line = (" "):rep(self.render_tree.width)
		-- for i = 1, self.render_tree.height do
		-- 	table.insert(xd, line)
		-- end
		-- vim.api.nvim_buf_set_lines(self.bufnr, 0, -1, false, xd)
		--
		-- for _, box in ipairs(_XDDD) do
		-- 	vim.api.nvim_buf_set_extmark(self.bufnr, ns, box.y, box.x, {
		-- 		virt_text = { { box.node.props } },
		-- 		end_col = box.x + box.width,
		-- 		virt_text_win_col = box.x,
		-- 		strict = false,
		-- 	})
		-- end
		-- self.render_tree:layout()
		-- self.render_tree.view:layout()
		-- log.info(self.root)
		-- self.root.current.state_node:print()
		-- self:commit()
	end)
end

function Renderer:rerender()
	u.measure_time("--- re-render", function()
		self.reconciler:reconcile()
		self.render_tree = markup.Render.Tree(self.root)
		self:commit()
	end)
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
