local markup = require("markup.core")
local u = require("markup.utils") ---@diagnostic disable-line: unused-local
local log = require("markup.logger") ---@diagnostic disable-line: unused-local

---@alias markup.Window.position "float"|"top"|"right"|"bottom"|"left"

---@class markup.Window.props
---@field winid integer
---@field bufnr integer
---@field ns_id integer
---@field buf_opts table<any, any>
---@field win_opts table<any, any>
---@field keys table<string, string>
---@field enter boolean
---@field show boolean
---@field config vim.api.keyset.win_config
---@field position markup.Window.position
---@field keymaps table<string, string>

---@class markup.Window : markup.Object
---@field protected _ markup.Window.props
---@field winid integer
---@field bufnr integer
local Window = markup.Object("markup.window")

local style = {
	minimal = {
		buf_opts = {},
		win_opts = {
			winhighlight = "Normal:MarkupNormal,NormalNC:MarkupNormalNC,WinBar:MarkupWinBar,WinBarNC:MarkupWinBarNC",
			cursorcolumn = false,
			cursorline = false,
			cursorlineopt = "both",
			fillchars = "eob: ,lastline:…",
			list = false,
			listchars = "extends:…,tab:  ",
			number = false,
			relativenumber = false,
			signcolumn = "no",
			spell = false,
			winbar = "",
			statuscolumn = "",
			wrap = false,
			sidescrolloff = 0,
			foldenable = false,
			foldcolumn = "0",
			colorcolumn = "",
			winfixbuf = true,
		},
	},
}

function Window.static:_normalize_props(props)
	local defaults = {
		ns_id = vim.api.nvim_create_namespace("markup.window"),
		enter = false,
		show = true,
		minimal = true,
		position = "float",
		config = {},
		buf_opts = {},
		win_opts = {},
		keys = {
			q = "close",
		},
		keymaps = {},
	}

	props = vim.tbl_deep_extend("force", defaults, props or {})

	if props.minimal then
		props = vim.tbl_deep_extend("force", style.minimal, props)
	end

	return props
end

---@param props markup.Window.constructor.props
function Window:init(props)
	self._ = Window.static:_normalize_props(props)
	self.bufnr = self._.bufnr == 0 and vim.api.nvim_get_current_buf() or self._.bufnr
	self.winid = self._.winid == 0 and vim.api.nvim_get_current_win() or self._.winid

	if self._.show == true then
		self:show()
	end

	self:after_init()
end

function Window:after_init() end

local defaults = {
	split = {
		relative = "editor",
		height = 0.4,
		width = 0.4,
	},
	float = {
		relative = "editor",
		height = 0.9,
		width = 0.9,
		zindex = 50,
	},
}

function Window:_is_float()
	return self._.position == "float"
end

---@return vim.api.keyset.win_config
function Window:_win_config()
	local config = self._.config

	if self:_is_float() then
		config = vim.tbl_deep_extend("force", defaults.float, config)
	else
		config = vim.tbl_deep_extend("force", defaults.split, config)
	end

	local parent = self:parent_size()
	config.height = config.height == 0 and parent.height or config.height
	config.width = config.width == 0 and parent.width or config.width
	config.height = math.floor(config.height < 1 and parent.height * config.height or config.height)
	config.width = math.floor(config.width < 1 and parent.width * config.width or config.width)

	if self:_is_float() and config.relative ~= "cursor" then
		config.row = config.row or math.floor((parent.height - config.height) / 2)
		config.col = config.col or math.floor((parent.width - config.width) / 2)
	end

	return config
end

function Window:show()
	self:win_open()
	self:apply_opts()
end

---@param preserve_buf? boolean
function Window:close(preserve_buf)
	vim.schedule(function()
		self:win_close()
		if preserve_buf ~= true then
			self:buf_delete()
		end
		-- if self.augroup then
		--     pcall(vim.api.nvim_del_augroup_by_id, self.augroup)
		--     self.augroup = nil
		-- end
	end)
end

function Window:buf_delete()
	if self:buf_is_valid() then
		vim.api.nvim_buf_delete(self.bufnr, { force = true })
	end
	self.bufnr = nil
end

function Window:win_close()
	if self:win_is_valid() then
		vim.api.nvim_win_close(self.winid, true)
	end
	self.winid = nil
end

function Window:hide()
	self:close(true)
end

function Window:toggle()
	if self:is_valid() then
		self:hide()
	else
		self:show()
	end
end

function Window:buf_open()
	if not self.bufnr or not self:buf_is_valid() then
		self.bufnr = vim.api.nvim_create_buf(false, true)
	end

	return self.bufnr
end

function Window:map(mode, key, spec, opts)
	self._.keymaps[key] = mode

	vim.keymap.set(mode, key, spec, {
		buffer = self.bufnr,
		silent = true,
		remap = true,
		nowait = true,
	})
end

function Window:unmap(mode, key)
	pcall(vim.api.nvim_buf_del_keymap, self.bufnr, mode, key)
end

function Window:clear_keymaps()
	for key, mode in pairs(self._.keymaps) do
		self:unmap(mode, key)
	end

	self._.keymaps = {}
end

local split_commands = {
	editor = {
		top = "topleft",
		right = "vertical botright",
		bottom = "botright",
		left = "vertical topleft",
	},
	win = {
		top = "aboveleft",
		right = "vertical rightbelow",
		bottom = "belowright",
		left = "vertical leftabove",
	},
}

function Window:_split_cmd(relative, position, size)
	local cmd = split_commands[relative][position]
	return ("silent noswapfile %s %s split"):format(cmd, size)
end

function Window:win_open()
	self:buf_open()

	vim.keymap.set("n", "<CR>", function()
		self:handle_on_submit()
	end)

	vim.keymap.set("n", "r", function()
		self:render()
	end)

	if self:win_is_valid() then
		return
	end

	local props = self._
	local config = self:_win_config()

	if self:_is_float() then
		self.winid = vim.api.nvim_open_win(self.bufnr, props.enter, config)
	else
		local parent = config.win or 0
		local size = config.vertical and config.width or config.height

		vim.api.nvim_win_call(parent, function()
			vim.cmd(self:_split_cmd(config.relative, props.position, size))
			vim.api.nvim_win_set_buf(0, self.bufnr)
			self.winid = vim.api.nvim_get_current_win()
		end)

		if props.enter then
			vim.api.nvim_set_current_win(self.winid)
		end
	end
end

function Window:apply_opts()
	self:apply_buf_opts()
	self:apply_win_opts()
end

function Window:apply_buf_opts()
	u.buf_set_opts(self.bufnr, self._.buf_opts)
end

function Window:apply_win_opts()
	u.win_set_opts(self.winid, self._.win_opts)
end

function Window:buf_is_valid()
	return self.bufnr and vim.api.nvim_buf_is_valid(self.bufnr)
end

function Window:win_is_valid()
	return self.winid and vim.api.nvim_win_is_valid(self.winid)
end

function Window:is_valid()
	return self:win_is_valid()
		and self:buf_is_valid()
		and vim.api.nvim_win_get_buf(self.winid) == self.bufnr
end

---@param name string
function Window:buf_get_option_value(name)
	assert(self:buf_is_valid(), "Buffer is not valid")
	return vim.api.nvim_get_option_value(name, { buf = self.bufnr })
end

---@param name string
---@param value any
function Window:buf_set_option_value(name, value)
	assert(self:buf_is_valid(), "Buffer is not valid")
	vim.api.nvim_set_option_value(name, value, { buf = self.bufnr })
end

---@param name string
function Window:win_get_option_value(name)
	assert(self:win_is_valid(), "Window is not valid")
	return vim.api.nvim_get_option_value(name, { win = self.winid, scope = "local" })
end

---@param name string
---@param value any
function Window:win_set_option_value(name, value)
	assert(self:win_is_valid(), "Window is not valid")
	vim.api.nvim_set_option_value(name, value, { win = self.winid, scope = "local" })
end

---@param start number
---@param end_ number
---@param strict_indexing boolean
---@param replacement string[]
function Window:buf_set_lines(start, end_, strict_indexing, replacement)
	assert(self:buf_is_valid(), "Buffer is not valid")
	vim.api.nvim_buf_set_lines(self.bufnr, start, end_, strict_indexing, replacement)
end

---@param start number
---@param end_ number
---@param strict_indexing boolean
function Window:buf_get_lines(start, end_, strict_indexing)
	assert(self:buf_is_valid(), "Buffer is not valid")
	return vim.api.nvim_buf_get_lines(self.bufnr, start, end_, strict_indexing)
end

---@param ns_id? integer
---@param line_start? integer
---@param line_end? integer
function Window:buf_clear_namespace(ns_id, line_start, line_end)
	ns_id = ns_id or self._.ns_id
	vim.api.nvim_buf_clear_namespace(self.bufnr, ns_id, line_start or 0, line_end or -1)
end

---@param line integer
---@param col integer
---@param opts vim.api.keyset.set_extmark
---@return integer
function Window:buf_set_extmark(ns_id, line, col, opts)
	ns_id = ns_id or self._.ns_id
	return vim.api.nvim_buf_set_extmark(self.bufnr, ns_id, line, col, opts)
end

---@param start integer
---@param end_ integer
---@param opts vim.api.keyset.get_extmarks
function Window:buf_get_extmarks(start, end_, opts)
	return vim.api.nvim_buf_get_extmarks(self.bufnr, self._.ns_id, start, end_, opts)
end

---@param buffer_opts? table<any, any>
---@param window_opts? table<any, any>
function Window:set_opts(buffer_opts, window_opts)
	if buffer_opts then
		u.buf_set_opts(self.bufnr, buffer_opts)
	end
	if window_opts then
		u.win_set_opts(self.winid, window_opts)
	end
end

---@param option string
---@param fn fun()
---@param inverse? boolean
function Window:with_buf_option(option, fn, inverse)
	local value = self:buf_get_option_value(option)
	if not value then
		inverse = inverse or false
		self:buf_set_option_value(option, not inverse)
		fn()
		self:buf_set_option_value(option, inverse)
	else
		fn()
	end
end

---@param option string
---@param fn fun()
---@param inverse? boolean
function Window:with_win_option(option, fn, inverse)
	local value = self:win_get_option_value(option)
	if not value then
		inverse = inverse or false
		self:win_set_option_value(option, not inverse)
		fn()
		self:win_set_option_value(option, inverse)
	else
		fn()
	end
end

function Window:_update()
	if self:is_valid() then
		self:apply_opts()
		if self:_is_float() then
			-- opts.noautocmd = nil
			vim.api.nvim_win_set_config(self.winid, self:_win_config())
		end
	end
end

function Window:win_get_width()
	return vim.api.nvim_win_get_width(self.winid)
end

function Window:win_set_width(width)
	vim.api.nvim_win_set_width(self.winid, width)
end

function Window:win_get_height()
	return vim.api.nvim_win_get_height(self.winid)
end

function Window:win_set_height(height)
	vim.api.nvim_win_set_height(self.winid, height)
end

function Window:parent_size()
	local relative = self._.config.relative

	local height = relative == "win" and vim.api.nvim_win_get_height(self._.config.win)
		or vim.o.lines
	local width = relative == "win" and vim.api.nvim_win_get_width(self._.config.win)
		or vim.o.columns

	return { width = width, height = height }
end

---@class markup.Window.constructor.props
---@field winid? integer bind to an existing window
---@field bufnr? integer bind to an existing buffer
---@field ns_id? integer namespace id
---@field buf_opts? table<any, any> buffer options
---@field win_opts? table<any, any> window options
---@field keys? table<string, string> key mappings
---@field enter? boolean focus on window creation
---@field show? boolean show window on creation
---@field config? vim.api.keyset.win_config window configuration
---@field position? markup.Window.position window position

---@alias markup.Window.constructor fun(props?: markup.Window.constructor.props): markup.Window

---@type markup.Window.constructor
local MarkupWindow = Window ---@diagnostic disable-line: assign-type-mismatch

return MarkupWindow
