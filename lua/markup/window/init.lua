local NuiLine = require("nui.line")
local NuiText = require("nui.text")
local Opts = require("leetcode-ui.opts")
local utils = require("leetcode-ui.utils")
local log = require("leetcode.logger")
local Object = require("markup.object")

---@class markup.Window.props
---@field winid integer
---@field bufnr integer
---@field linenr_start integer start line number (1-indexed)
---@field byte_start integer start byte position (0-indexed)
---@field linenr_end integer end line number (1-indexed)
---@field byte_end integer end byte position (0-indexed)
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
		linenr_start = 1,
		byte_start = 0,
		linenr_end = nil,
		byte_end = nil,
	}, props)
end

function Window:draw()
	self:clear()

	self._.linenr_start = 0
	self._.linenr_end = 0

	self._.child:draw(self)
end

function Window:clear()
	self:with_modifiable(function()
		vim.api.nvim_buf_set_lines(self._.bufnr, 0, -1, false, {})
	end)
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
