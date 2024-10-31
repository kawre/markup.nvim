local markup = require("markup")
local log = require("markup.logger")

---@class markup.Renderer.props : markup.Window.props
---@field grid integer[]
---@field ns_id integer
---@field child markup.Element

---@class markup.Renderer : markup.Window
---@field _ markup.Renderer.props
local Renderer = markup.Window:extend("MarkupRenderer")

---@param props markup.Renderer.constructor.props
function Renderer:init(props)
	if type(props) == "number" then
		props = { winid = props }
	end

	props = vim.tbl_deep_extend("force", {
		ns_id = -1,
		grid = { 0 },
	}, props)
	Renderer.super.init(self, props)

	local u = require("markup.utils")
	u.buf_set_opts(self._.bufnr, {
		modifiable = true,
		buflisted = false,
		matchpairs = "",
		swapfile = false,
		buftype = "nofile",
		filetype = "preview",
		synmaxcol = 0,
	})
	u.win_set_opts(self._.winid, {
		wrap = false,
		colorcolumn = "",
		foldlevel = 999,
		foldcolumn = "0",
		cursorcolumn = false,
		cursorline = false,
		number = false,
		relativenumber = false,
		list = false,
		spell = false,
		signcolumn = "no",
		winfixbuf = true,
	})
end

---Get current grid position (row, col)
---@param row_at? integer
---@return integer, integer
function Renderer:get_pos(row_at)
	local row = row_at or #self._.grid
	return row, self._.grid[row]
end

---Get current grid position (row, col)
---@param value integer
---@param row_at? integer
---@return integer, integer
function Renderer:inc_pos(value, row_at)
	local row = row_at or #self._.grid
	local col = self._.grid[row] + value
	self._.grid[row] = col
	return row, col
end

function Renderer:draw()
	self:clear()

	self._.grid = { 0 }

	self:with_modifiable(function()
		self._.child:draw(self, nil)
	end)
end

function Renderer:clear()
	self:with_modifiable(function()
		vim.api.nvim_buf_set_lines(self._.bufnr, 0, -1, false, {})
	end)
end

---@param n? integer
function Renderer:endl(n)
	for _ = 1, n or 1 do
		table.insert(self._.grid, 0)
		local row = self:get_pos()
		vim.api.nvim_buf_set_lines(self._.bufnr, row, -1, false, { "" })
	end
end

---Add padding after line
---@param n integer
---@param row_at? integer
function Renderer:pad(n, row_at)
	local row, col = self:get_pos()
	row = row_at or row
	vim.api.nvim_buf_set_text(self._.bufnr, row, col, row, col, { (" "):rep(n) })
	self:inc_pos(n, row)
end

---Add padding before line
---@param n integer
---@param row_at? integer
function Renderer:pad_before(n, row_at)
	local row = self:get_pos()
	row = row_at or row
	vim.api.nvim_buf_set_text(self._.bufnr, row, 0, row, 0, { (" "):rep(n) })
	self:inc_pos(n, row)
end

function Renderer:with_modifiable(fn)
	local bufnr = self._.bufnr
	if not (bufnr and vim.api.nvim_buf_is_valid(bufnr)) then
		return
	end

	local modi = vim.api.nvim_buf_get_option(bufnr, "modifiable")
	if not modi then
		vim.api.nvim_buf_set_option(bufnr, "modifiable", true)
	end
	fn()
	if not modi then
		vim.api.nvim_buf_set_option(bufnr, "modifiable", false)
	end
end

---@class markup.Renderer.constructor.props
---@field winid integer
---@field bufnr integer
---@field child markup.Element
---@field ns_id? integer

---@alias markup.Renderer.constructor fun(props: markup.Renderer.constructor.props): markup.Renderer

---@type markup.Renderer.constructor
local MarkupRenderer = Renderer

return MarkupRenderer
