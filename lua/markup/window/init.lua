local Object = require("markup.object")

---@class markup.Window.props
---@field winid integer
---@field bufnr integer
---@field row integer start line number (1-indexed)
---@field col integer start byte position (0-indexed)
---@field ns_id integer
---@field child markup.Element

---@class markup.Window : markup.Object
---@field _ markup.Window.props
local Window = Object("MarkupWindow")

---@param props markup.Window.constructor.props
function Window:init(props)
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

function Window:draw()
	self:clear()

	self._.row = 0
	self._.col = 0

	self:with_modifiable(function()
		self._.child:draw(self)
	end)
end

function Window:clear()
	self:with_modifiable(function()
		vim.api.nvim_buf_set_lines(self._.bufnr, 0, -1, false, {})
	end)
end

function Window:endl()
	self._.row = self._.row + 1
	vim.api.nvim_buf_set_lines(self._.bufnr, self._.row, -1, false, { "" })
	self._.col = 0
end

function Window:with_modifiable(fn)
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

---@class markup.Window.constructor.props
---@field winid integer
---@field bufnr integer
---@field child markup.Element
---@field ns_id? integer

---@alias markup.Window.constructor fun(props: markup.Window.constructor.props): markup.Window

---@type markup.Window.constructor
local MarkupWindow = Window

return MarkupWindow
