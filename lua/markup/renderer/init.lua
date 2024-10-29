local markup = require("markup")

---@class markup.Renderer.props : markup.Window.props
---@field winid integer
---@field bufnr integer
---@field prev table
---@field row integer start line number (1-indexed)
---@field col integer start byte position (0-indexed)
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

	self._ = vim.tbl_deep_extend("force", {
		winid = 0,
		bufnr = 0,
		child = nil,
		ns_id = -1,
		linenr_start = 0,
		byte_start = 0,
		prev = {},
	}, props)

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

function Renderer:draw()
	self:clear()

	self._.row = 0
	self._.col = 0

	self:with_modifiable(function()
		self._.child:draw(self)
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
		self._.prev[self._.row] = self._.col

		self._.row = self._.row + 1
		vim.api.nvim_buf_set_lines(self._.bufnr, self._.row, -1, false, { "" })
		self._.col = 0
	end
end

function Renderer:pad(n)
	local bufnr, col, row = self._.bufnr, self._.col, self._.row
	vim.api.nvim_buf_set_text(bufnr, row, col, row, col, { (" "):rep(n) })
	self._.col = self._.col + n
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
