local styles = require("markup.core.window.styles")

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

local win_opts = {
	"anchor",
	"border",
	"bufpos",
	"col",
	"external",
	"fixed",
	"focusable",
	"footer",
	"footer_pos",
	"height",
	"hide",
	"noautocmd",
	"relative",
	"row",
	"style",
	"title",
	"title_pos",
	"width",
	"win",
	"zindex",
}

---@type table<string, string[]>
local borders = {
	left = { "", "", "", "", "", "", "", "│" },
	right = { "", "", "", "│", "", "", "", "" },
	top = { "", "─", "", "", "", "", "", "" },
	bottom = { "", "", "", "", "", "─", "", "" },
	hpad = { "", "", "", " ", "", "", "", " " },
	vpad = { "", " ", "", "", "", " ", "", "" },
}

---@class markup.Window.config: vim.api.keyset.win_config
---@field style? string merges with config from `Snacks.config.styles[style]`
---@field show? boolean Show the window immediately (default: true)
---@field height? number|fun(self:snacks.win):number Height of the window. Use <1 for relative height. 0 means full height. (default: 0.9)
---@field width? number|fun(self:snacks.win):number Width of the window. Use <1 for relative width. 0 means full width. (default: 0.9)
---@field min_height? number Minimum height of the window
---@field max_height? number Maximum height of the window
---@field min_width? number Minimum width of the window
---@field max_width? number Maximum width of the window
---@field col? number|fun(self:snacks.win):number Column of the window. Use <1 for relative column. (default: center)
---@field row? number|fun(self:snacks.win):number Row of the window. Use <1 for relative row. (default: center)
---@field minimal? boolean Disable a bunch of options to make the window minimal (default: true)
---@field position? "float"|"bottom"|"top"|"left"|"right"
---@field border? "none"|"top"|"right"|"bottom"|"left"|"hpad"|"vpad"|"rounded"|"single"|"double"|"solid"|"shadow"|string[]|false
---@field buf? number If set, use this buffer instead of creating a new one
---@field file? string If set, use this file instead of creating a new buffer
---@field enter? boolean Enter the window after opening (default: false)
---@field backdrop? number|false|snacks.win.Backdrop Opacity of the backdrop (default: 60)
---@field wo? vim.wo|{} window options
---@field bo? vim.bo|{} buffer options
---@field b? table<string, any> buffer local variables
---@field w? table<string, any> window local variables
---@field ft? string filetype to use for treesitter/syntax highlighting. Won't override existing filetype
---@field scratch_ft? string filetype to use for scratch buffers
---@field keys? table<string, false|string|fun(self: snacks.win)|snacks.win.Keys> Key mappings
---@field on_buf? fun(self: snacks.win) Callback after opening the buffer
---@field on_win? fun(self: snacks.win) Callback after opening the window
---@field on_close? fun(self: snacks.win) Callback after closing the window
---@field fixbuf? boolean don't allow other buffers to be opened in this window
---@field text? string|string[]|fun():(string[]|string) Initial lines to set in the buffer
---@field actions? table<string, snacks.win.Action.spec> Actions that can be used in key mappings
---@field resize? boolean Automatically resize the window when the editor is resized

---@class markup.Window.opts
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

---@class markup.Window
---@field protected opts markup.Window.props
---@field ns integer
---@field win integer
---@field buf integer
---@overload fun(opts?: snacks.win.Config | {}): markup.Window
local M = setmetatable({}, {
	__call = function(t, ...)
		return t.new(...)
	end,
})
M.__index = M

--@private
---@param ...? snacks.win.Config|string|{}
---@return snacks.win.Config
function M.resolve(...)
	local done = {} ---@type table<string, boolean>
	local merge = {} ---@type snacks.win.Config[]
	local stack = {}
	for i = 1, select("#", ...) do
		local next = select(i, ...) ---@type snacks.win.Config|string?
		if next then
			table.insert(stack, next)
		end
	end
	while #stack > 0 do
		local next = table.remove(stack)
		next = type(next) == "string" and Snacks.config.styles[next] or next
		---@cast next snacks.win.Config?
		if next and type(next) == "table" then
			table.insert(merge, 1, next)
			if next.style and not done[next.style] then
				done[next.style] = true
				table.insert(stack, next.style)
			end
		end
	end
	local ret = #merge == 0 and {}
		or #merge == 1 and merge[1]
		or vim.tbl_deep_extend("force", {}, unpack(merge))
	ret.style = nil
	return ret
end

---@return markup.Window
function M.new(opts)
	local self = setmetatable({}, M)

	self.id = Markup.util.gen_id()
	opts = M.resolve(styles.default, opts)
	if opts.minimal then
		opts = M.resolve("minimal", opts)
	end
	if opts.position == "float" then
		opts = M.resolve("float", opts)
	else
		opts = M.resolve("split", opts)
		local vertical = opts.position == "left" or opts.position == "right"
		opts.wo.winfixheight = not vertical
		opts.wo.winfixwidth = vertical
	end
	if opts.relative == "win" then
		opts.win = opts.win or vim.api.nvim_get_current_win()
	end

	self.keys = {}
	self.events = {}
	local done = {} ---@type table<string, snacks.win.Keys>
	for key, spec in pairs(opts.keys) do
		if spec then
			if type(spec) == "string" then
				spec = { key, spec, desc = spec }
			elseif type(spec) == "function" then
				spec = { key, spec }
			elseif type(spec) == "table" and spec[1] and not spec[2] then
				spec = vim.deepcopy(spec) -- deepcopy just in case
				spec[1], spec[2] = key, spec[1]
			end
			---@cast spec snacks.win.Keys
			local lhs = Snacks.util.normkey(spec[1] or "")
			local mode = type(spec.mode) == "table" and spec.mode or { spec.mode or "n" }
			---@cast mode string[]
			mode = #mode == 0 and { "n" } or mode
			for _, m in ipairs(mode) do
				local k = m .. ":" .. lhs
				if done[k] then
					Snacks.notify.warn(
						("# Duplicate key mapping for `%s` mode=%s (check case):\n```lua\n%s\n```\n```lua\n%s\n```"):format(
							lhs,
							m,
							vim.inspect(done[k]),
							vim.inspect(spec)
						)
					)
				end
				done[k] = spec
			end
			table.insert(self.keys, spec)
		end
	end

	-- self:on("WinClosed", self.on_close, { win = true })
	--
	-- -- update window size when resizing
	-- self:on("VimResized", self.on_resize)

	---@cast opts markup.Window.config
	self.opts = opts
	if opts.show ~= false then
		self:show()
	end
	return self
end

---@private
function M:win_opts()
	local opts = {} ---@type vim.api.keyset.win_config
	for _, k in ipairs(win_opts) do
		opts[k] = self.opts[k]
	end

	opts.border = opts.border and (borders[opts.border] or opts.border) or "none"

	if opts.relative == "cursor" then
		self.opts.row = self.opts.row or 0
		self.opts.col = self.opts.col or 0
	end

	-- local dim = self:dim()
	-- opts.height, opts.width = dim.height, dim.width
	-- opts.row, opts.col = dim.row, dim.col

	if opts.title_pos and not opts.title then
		opts.title_pos = nil
	end
	if opts.footer_pos and not opts.footer then
		opts.footer_pos = nil
	end

	if vim.fn.has("nvim-0.10") == 0 then
		opts.footer, opts.footer_pos = nil, nil
	end

	-- if not self:has_border() then
	-- 	opts.title, opts.footer = nil, nil
	-- 	opts.title_pos, opts.footer_pos = nil, nil
	-- end
	return opts
end

---@private
function M:open_win()
	local relative = self.opts.relative or "editor"
	local position = self.opts.position or "float"
	local enter = self.opts.enter == nil or self.opts.enter or false
	if self.opts.focusable == false then
		enter = false
	end
	local opts = self:win_opts()
	if position == "float" then
		self.win = vim.api.nvim_open_win(self.buf, enter, opts)
	elseif position == "current" then
		self.win = vim.api.nvim_get_current_win()
	else
		local parent = self.opts.win or 0
		local vertical = position == "left" or position == "right"
		if parent == 0 then
			for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
				if
					vim.w[win].snacks_win
					and vim.w[win].snacks_win.relative == relative
					and vim.w[win].snacks_win.position == position
				then
					parent = win
					relative = "win"
					position = vertical and "bottom" or "right"
					vertical = not vertical
					break
				end
			end
		end
		local cmd = split_commands[relative][position]
		local size = vertical and opts.width or opts.height
		vim.api.nvim_win_call(parent, function()
			vim.cmd("silent noswapfile " .. cmd .. " " .. size .. "split")
			vim.api.nvim_win_set_buf(0, self.buf)
			self.win = vim.api.nvim_get_current_win()
		end)
		if enter then
			vim.api.nvim_set_current_win(self.win)
		end
		vim.schedule(function()
			self:equalize()
		end)
	end
	vim.w[self.win].snacks_win = {
		id = self.id,
		position = self.opts.position,
		relative = self.opts.relative,
	}
end

---@private
function M:open_buf()
	if self.buf and vim.api.nvim_buf_is_valid(self.buf) then
		-- keep existing buffer
		self.buf = self.buf
	elseif self.scratch_buf and vim.api.nvim_buf_is_valid(self.scratch_buf) then
		-- keep existing scratch buffer
		self.buf = self.scratch_buf
	elseif self.opts.file then
		self.buf = vim.fn.bufadd(self.opts.file)
		if not vim.api.nvim_buf_is_loaded(self.buf) then
			vim.bo[self.buf].readonly = true
			vim.bo[self.buf].swapfile = false
			vim.fn.bufload(self.buf)
			vim.bo[self.buf].modifiable = false
		end
	elseif self.opts.buf then
		self.buf = self.opts.buf
	else
		self:scratch()
	end
	return self.buf
end

function M:is_floating()
	return self:valid() and vim.api.nvim_win_get_config(self.win).zindex ~= nil
end

function M:update()
	if self:valid() then
		Markup.util.bo(self.buf, self.opts.bo)
		Markup.util.wo(self.win, self.opts.wo)
		if self:is_floating() then
			local opts = self:win_opts()
			opts.noautocmd = nil
			vim.api.nvim_win_set_config(self.win, opts)
		end
	end
end

function M:show()
	if self:valid() then
		self:update()
		return self
	end
	self.augroup = vim.api.nvim_create_augroup("snacks_win_" .. self.id, { clear = true })

	self:open_buf()

	Markup.debug(self.buf)
	Markup.debug(self.win)

	-- buffer local variables
	for k, v in pairs(self.opts.b or {}) do
		vim.b[self.buf][k] = v
	end

	self:open_win()
	self.closed = false
	-- -- window local variables
	for k, v in pairs(self.opts.w or {}) do
		vim.w[self.win][k] = v
	end
end

function M:scratch()
	if self.buf == self.scratch_buf and self:buf_valid() then
		return
	end
	self.buf = vim.api.nvim_create_buf(false, true)
	vim.bo[self.buf].swapfile = false
	self.scratch_buf = self.buf
	local text = type(self.opts.text) == "function" and self.opts.text() or self.opts.text
	text = type(text) == "string" and vim.split(text, "\n") or text
	if text then
		---@cast text string[]
		vim.api.nvim_buf_set_lines(self.buf, 0, -1, false, text)
	end
	if not self.opts.bo.filetype then
		if self.opts.scratch_ft then
			vim.bo[self.buf].filetype = self.opts.scratch_ft
		else
			vim.bo[self.buf].filetype = self.opts.bo.filetype or "snacks_win"
		end
		vim.bo[self.buf].syntax = ""
	end
	if self:win_valid() then
		vim.api.nvim_win_set_buf(self.win, self.buf)
	end
end

-- function M:show()
-- 	if self:valid() then
-- 		self:update()
-- 		return self
-- 	end
-- 	self.augroup = vim.api.nvim_create_augroup("snacks_win_" .. self.id, { clear = true })
--
-- 	self:open_buf()
--
-- 	-- buffer local variables
-- 	for k, v in pairs(self.opts.b or {}) do
-- 		vim.b[self.buf][k] = v
-- 	end
--
-- 	-- OPTIM: prevent treesitter or syntax highlighting to attach on FileType if it's not already enabled
-- 	local optim_hl = not vim.b[self.buf].ts_highlight and vim.bo[self.buf].syntax == ""
-- 	vim.b[self.buf].ts_highlight = optim_hl or vim.b[self.buf].ts_highlight
-- 	Snacks.util.bo(self.buf, self.opts.bo)
-- 	vim.b[self.buf].ts_highlight = not optim_hl and vim.b[self.buf].ts_highlight or nil
--
-- 	if self.opts.on_buf then
-- 		self.opts.on_buf(self)
-- 	end
--
-- 	self:open_win()
-- 	self.closed = false
-- 	-- window local variables
-- 	for k, v in pairs(self.opts.w or {}) do
-- 		vim.w[self.win][k] = v
-- 	end
-- 	if Snacks.util.is_transparent() then
-- 		self.opts.wo.winblend = 0
-- 	end
-- 	Snacks.util.wo(self.win, self.opts.wo)
-- 	if self.opts.on_win then
-- 		self.opts.on_win(self)
-- 	end
--
-- 	-- syntax highlighting
-- 	local ft = self.opts.ft or vim.bo[self.buf].filetype
-- 	if
-- 		ft
-- 		and not ft:find("^snacks_")
-- 		and not vim.b[self.buf].ts_highlight
-- 		and vim.bo[self.buf].syntax == ""
-- 	then
-- 		local lang = vim.treesitter.language.get_lang(ft)
-- 		if not (lang and pcall(vim.treesitter.start, self.buf, lang)) then
-- 			vim.bo[self.buf].syntax = ft
-- 		end
-- 	end
--
-- 	for _, event in ipairs(self.events) do
-- 		self:_on(event.event, event)
-- 	end
--
-- 	-- swap buffers when opening a new buffer in the same window
-- 	vim.api.nvim_create_autocmd("BufWinEnter", {
-- 		group = self.augroup,
-- 		nested = true,
-- 		callback = function()
-- 			return self:fixbuf()
-- 		end,
-- 	})
--
-- 	-- self:map()
-- 	-- self:drop()
--
-- 	return self
-- end

---@param buf number
function M:set_buf(buf)
	assert(self:valid(), "Window is not valid")
	self.buf = buf
	vim.api.nvim_win_set_buf(self.win, buf)
	Snacks.util.wo(self.win, self.opts.wo)
end

function M:on_current_tab()
	return self:win_valid()
		and vim.api.nvim_get_current_tabpage() == vim.api.nvim_win_get_tabpage(self.win)
end

function M:buf_valid()
	return self.buf and vim.api.nvim_buf_is_valid(self.buf)
end

function M:win_valid()
	return self.win and vim.api.nvim_win_is_valid(self.win)
end

function M:valid()
	return self:win_valid() and self:buf_valid() and vim.api.nvim_win_get_buf(self.win) == self.buf
end

return M
