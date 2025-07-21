local markup = require("markup.core")

---@alias markup.Window.position "float"|"top"|"right"|"bottom"|"left"

---@class markup.Window.props
---@field id integer
---@field bufnr integer
---@field ns_id integer
---@field buf_opts table<any, any>
---@field win_opts table<any, any>
---@field bo table<any, any>
---@field wo table<any, any>
---@field keys table<string, string>
---@field enter boolean
---@field show boolean
---@field config vim.api.keyset.win_config
---@field position markup.Window.position
---@field keymaps { active?: table, pending?: table }

---@class markup.Window2 : markup.Object
---@field protected _ markup.Window.props
---@field id integer
---@field bufnr integer
---@field ns integer
---@field win markup.Window.win
---@field buf markup.Window.win
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
	self.id = self._.id == 0 and vim.api.nvim_get_current_win() or self._.id
	self.ns = self._.ns_id

	self.win = Win(self)
	self.buf = Buf(self)

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
	self:open()
	self:apply_opts()
end

---@param preserve_buf? boolean
function Window:close(preserve_buf)
	vim.schedule(function()
		self.win:close()
		if preserve_buf ~= true then
			self.buf:delete()
		end
		-- if self.augroup then
		--     pcall(vim.api.nvim_del_augroup_by_id, self.augroup)
		--     self.augroup = nil
		-- end
	end)
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

function Window:map(mode, key, spec, opts)
	self._.keymaps[key] = mode

	vim.keymap.set(mode, key, spec, {
		buffer = self.bufnr,
		silent = true,
		remap = true,
		nowait = true,
	})
end

function Window:clear_keymaps()
	if not self._.keymaps.active then
		return
	end

	for key, map in pairs(self._.keymaps.active) do
		self.buf:del_keymap(map.mode, key)
	end

	self._.keymaps.active = nil
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
	},
}

function Window:_split_cmd(relative, position, size)
	local cmd = split_commands[relative][position]
	return ("silent noswapfile %s %s split"):format(cmd, size)
end

function Window:open()
	self.buf:open()

	self.buf:set_keymap("n", "<CR>", "", {
		callback = function()
			self:handle_on_submit()
		end,
	})

	if self.win:is_valid() then
		return
	end

	local props = self._
	local config = self:_win_config()

	if self:_is_float() then
		self.id = vim.api.nvim_open_win(self.bufnr, props.enter, config)
	else
		local parent = config.win or 0
		local size = config.vertical and config.width or config.height

		vim.api.nvim_win_call(parent, function()
			vim.cmd(self:_split_cmd(config.relative, props.position, size))
			vim.api.nvim_win_set_buf(0, self.bufnr)
			self.id = vim.api.nvim_get_current_win()
		end)

		if props.enter then
			vim.api.nvim_set_current_win(self.id)
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
	u.win_set_opts(self.id, self._.win_opts)
end

function Window:is_valid()
	return self.win:is_valid() and self.buf:is_valid() and self.win:get_buf() == self.bufnr
end

---@param buffer_opts? table<any, any>
---@param window_opts? table<any, any>
function Window:set_opts(buffer_opts, window_opts)
	if buffer_opts then
		u.buf_set_opts(self.bufnr, buffer_opts)
	end
	if window_opts then
		u.win_set_opts(self.id, window_opts)
	end
end

---@param option string
---@param fn fun()
---@param inverse? boolean
function Window:with_buf_option(option, fn, inverse)
	local value = self.buf:get_option_value(option)
	if not value then
		inverse = inverse or false
		self.buf:set_option_value(option, not inverse)
		fn()
		self.buf:set_option_value(option, inverse)
	else
		fn()
	end
end

---@param option string
---@param fn fun()
---@param inverse? boolean
function Window:with_win_option(option, fn, inverse)
	local value = self.win:get_option_value(option)
	if not value then
		inverse = inverse or false
		self.win:set_option_value(option, not inverse)
		fn()
		self.win:set_option_value(option, inverse)
	else
		fn()
	end
end

function Window:_update()
	if self:is_valid() then
		self:apply_opts()
		if self:_is_float() then
			self.win:set_config(self:_win_config())
		end
	end
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
---@field id? integer bind to an existing window
---@field bufnr? integer bind to an existing buffer
---@field ns_id? integer namespace id
---@field buf_opts? table<any, any> buffer options
---@field win_opts? table<any, any> window options
---@field keys? table<string, string> key mappings
---@field enter? boolean focus on window creation
---@field show? boolean show window on creation
---@field config? vim.api.keyset.win_config window configuration
---@field position? markup.Window.position window position

---@alias markup.Window.constructor fun(props?: markup.Window.constructor.props): markup.window

---@type markup.Window.constructor
local MarkupWindow = Window ---@diagnostic disable-line: assign-type-mismatch

return MarkupWindow
