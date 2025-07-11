local markup = require("markup.core")

local u = require("markup.utils") ---@diagnostic disable-line: unused-local
local log = require("markup.logger") ---@diagnostic disable-line: unused-local
local RenderNodeFactory = require("markup.core.factory.render-node")
local RendererFactory = require("markup.core.factory.renderer")

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
	u.measure_time("--- render", function()
		self.root = RendererFactory.create_root(self, element)
		self.reconciler = markup.Reconciler(self)
		self.reconciler:reconcile()
		self.reconciler:print()
		-- self.render_tree = RenderNodeFactory(self.root.current.state_node, "block")
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
