local markup = require("markup")

local u = require("markup.utils") ---@diagnostic disable-line: unused-local
local log = require("markup.logger") ---@diagnostic disable-line: unused-local

---@class markup.Renderer.props : markup.Window.props
---@field body markup.Element.content

---@class markup.Renderer : markup.Window
---@field protected super markup.Window
---@field _ markup.Renderer.props
local Renderer = markup.Window:extend("MarkupRenderer") ---@diagnostic disable-line: undefined-field

---------------------------------
---- Methods
---------------------------------

function Renderer:render()
	if not self:is_valid() then
		return
	end

	self:preserve_cursor(function()
		local root = markup.Block(self:body())
		self:render_tree(root)
	end)
end

---@param root markup.Element
function Renderer:render_tree(root)
	log.debug("RENDER")
	u.measure_time("Renderer:build tree", function()
		root:render_node(self) ---@diagnostic disable-line: missing-parameter
	end)

	u.measure_time("Renderer:draw lines", function()
		self:with_buf_option("modifiable", function()
			self:clear()
			for row, line in pairs(root:computed_lines()) do
				line:draw(self, row)
			end
		end)
	end)
end

---@param line_start? integer
---@param line_end? integer
function Renderer:buf_clear_namespace(line_start, line_end)
	Renderer.super.buf_clear_namespace(self, self._.ns_id, line_start, line_end)
end

function Renderer:clear()
	self:buf_clear_namespace()
	self:buf_set_lines(0, -1, false, {})
end

function Renderer:preserve_cursor(fn)
	local c = vim.api.nvim_win_get_cursor(self.winid)
	fn()
	vim.api.nvim_win_set_cursor(self.winid, c)
end

---------------------------------
---- Setters
---------------------------------

---@param body markup.Element.content
function Renderer:set_body(body)
	if type(body) == "function" then
		body = body()
	end
	self._.body = body
end

---------------------------------
---- Getters
---------------------------------

function Renderer:body()
	return self._.body or ""
end

---------------------------------
---- Initializer
---------------------------------

---@class markup.Renderer.constructor.props : markup.Window.constructor.props
---@field body? markup.Element.content

---@alias markup.Renderer.constructor fun(props: markup.Renderer.constructor.props): markup.Renderer

---@type markup.Renderer.constructor
local MarkupRenderer = Renderer ---@diagnostic disable-line: assign-type-mismatch

return MarkupRenderer
