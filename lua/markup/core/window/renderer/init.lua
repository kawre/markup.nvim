local markup = require("markup")

local u = require("markup.utils") ---@diagnostic disable-line: unused-local
local log = require("markup.logger") ---@diagnostic disable-line: unused-local

---@class markup.Renderer.props : markup.Window.props
---@field body markup.Element.children
---@field buttons markup.Element[]

---@class markup.Renderer : markup.Window
---@field protected super markup.Window
---@field protected _ markup.Renderer.props
---@field body markup.Element.children
---@field last_render integer
---@field cooldown_ms integer ms
local Renderer = markup.Window:extend("MarkupRenderer") ---@diagnostic disable-line: undefined-field

---------------------------------
---- Methods
---------------------------------

function Renderer:after_init()
	self.cooldown_ms = 100
	Renderer.super.after_init(self)
	self.body = self._.body
end

---@param body? markup.Element.children
function Renderer:render(body)
	body = body or self.body
	self:render_portal(function()
		local root = markup.Block(body)
		root:render_node(self) ---@diagnostic disable-line: missing-parameter
		for row, line in pairs(root:computed_lines()) do
			line:draw(self, row)
		end
		self.body = body
	end)
end

---@param fn fun()
function Renderer:render_portal(fn)
	if not self:is_valid() then
		error("Renderer is not valid")
	end

	local now = vim.uv.hrtime()
	local elapsed_ms = (now - (self.last_render or 0)) / 1e6
	if elapsed_ms < self.cooldown_ms then
		return
	end
	self.last_render = now

	u.measure_time("markup.Renderer:render", function()
		self:preserve_cursor(function()
			self:with_buf_option("modifiable", function()
				self:clear()
				fn()
			end)
		end)
	end)
end

-- ---@param root markup.Element
-- function Renderer:render_tree(root)
-- 	self:with_buf_option("modifiable", function()
-- 		self:clear()
-- 		root:render_node(self) ---@diagnostic disable-line: missing-parameter
-- 		for row, line in pairs(root:computed_lines()) do
-- 			line:draw(self, row)
-- 		end
-- 	end)
-- end

---@param line_start? integer
---@param line_end? integer
function Renderer:buf_clear_namespace(line_start, line_end)
	Renderer.super.buf_clear_namespace(self, self._.ns_id, line_start, line_end)
end

function Renderer:clear()
	self:buf_clear_namespace()
	self:buf_set_lines(0, -1, false, {})
	self:clear_keymaps()
	self._.buttons = {}
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
