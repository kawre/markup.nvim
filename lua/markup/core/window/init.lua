local markup = require("markup")

---@class markup.Window.props
---@field winid integer
---@field bufnr integer
---@field child markup.Element

---@class markup.Window : markup.Object
---@field _ markup.Window.props
local Window = markup.Object("MarkupWindow")

---@param props markup.Window.constructor.props
function Window:init(props)
	self._ = vim.tbl_deep_extend("force", {
		bufnr = 0,
		winid = 0,
		child = nil,
	}, props)
end

---@param buffer_opts? table<any, any>
---@param window_opts? table<any, any>
function Window:set_opts(buffer_opts, window_opts)
	local u = require("markup.utils")

	if buffer_opts then
		u.buf_set_opts(self._.bufnr, buffer_opts)
	end
	if window_opts then
		u.win_set_opts(self._.winid, window_opts)
	end
end

function Window:width()
	return vim.api.nvim_win_get_width(self._.winid)
end

function Window:height()
	return vim.api.nvim_win_get_height(self._.winid)
end

---@class markup.Window.constructor.props
---@field winid integer
---@field bufnr integer
---@field child markup.Element

---@alias markup.Window.constructor fun(props: markup.Window.constructor.props): markup.Window

---@type markup.Window.constructor
local MarkupWindow = Window

return MarkupWindow
