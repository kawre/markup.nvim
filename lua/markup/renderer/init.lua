local markup = require("markup")
local utils = require("markup.utils")
local log = require("markup.logger")

---@alias markup.Renderer.state.position { row: integer, col: integer }
---@alias markup.Renderer.state.box { width: integer, height: integer }

---@class markup.Renderer.state
---@field row_start? integer
---@field row_end? integer
---@field col_start? integer
---@field col_end? integer
---@field initial? markup.Renderer.state.position
---@field final? markup.Renderer.state.position
---@field lengths? integer[]
---@field box? markup.Renderer.state.box
---@field parent? markup.Element

---@class markup.Renderer.props : markup.Window.props
---@field grid integer[]
---@field ns_id integer
---@field child markup.Element
---@field state markup.Renderer.state[]

---@class markup.Renderer : markup.Window
---@field _ markup.Renderer.props
local Renderer = markup.Window:extend("MarkupRenderer")

---@param props markup.Renderer.constructor.props
function Renderer:init(props)
	props = self:normalize_props(props, {
		bufnr = nil,
		winid = nil,
		ns_id = -1,
		grid = { 0 },
		state = {},
	})

	Renderer.super.init(self, props)

	self:set_opts({
		modifiable = true,
		buflisted = false,
		matchpairs = "",
		swapfile = false,
		buftype = "nofile",
		filetype = "preview",
		synmaxcol = 0,
	}, {
		wrap = false,
		colorcolumn = "",
		foldenable = false,
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
	self:setup_autocmds()
end

function Renderer:normalize_props(props, defaults)
	local result = {}

	if type(props) == "number" then
		result.children = { markup.Text(props) }
	elseif getmetatable(props) then
		result.children = { props }
	else
		result = props
	end

	return vim.tbl_deep_extend("force", defaults or {}, result)
end

function Renderer:setup_autocmds()
	log.debug(self._.bufnr)
	vim.api.nvim_create_autocmd("WinResized", {
		buffer = self._.bufnr,
		callback = function()
			self:render()
		end,
	})
end

---Get grid position at row
---@param row_at? integer (0-indexed)
---@return integer, integer (row, col) (0-indexed, 0-indexed)
function Renderer:get_pos(row_at)
	local row = row_at or (#self._.grid - 1)
	return row, self._.grid[row + 1]
end

---Get grid column position at row
---@param row_at? integer (0-indexed)
---@return integer (col) (0-indexed)
function Renderer:get_col(row_at)
	return select(2, self:get_pos(row_at))
end

---increment grid position at row
---@param value integer
---@param row_at? integer (0-indexed)
---@return integer, integer (row, col) (0-indexed, 0-indexed)
function Renderer:inc_pos(value, row_at)
	local row = self:get_pos(row_at)
	local col = self._.grid[row + 1] + value
	self._.grid[row + 1] = col
	return row, col
end

function Renderer:render()
	local elapsed_ms, fps = utils.measure_time(function()
		self:clear_grid()
		self:with_modifiable(function()
			self._.child:render(self)
		end)
	end)

	log.debug(("elapsed time: %.2fms [FPS: %d]"):format(elapsed_ms, fps))
end

function Renderer:clear_grid()
	self:with_modifiable(function()
		vim.api.nvim_buf_set_lines(self._.bufnr, 0, -1, false, {})
	end)
	self._.grid = { 0 }
	self._.state = {}
end

---@param n? integer
function Renderer:endl(n)
	for _ = 1, n or 1 do
		table.insert(self._.grid, 0)
		local row = self:get_pos()
		vim.api.nvim_buf_set_lines(self._.bufnr, row, -1, false, { "" })
	end
end

---Add padding (row_at, col_at)
---@param n integer repeat
---@param row_at? integer (0-indexed)
---@param col_at? integer (0-indexed)
function Renderer:pad(n, row_at, col_at)
	local row, col = self:get_pos()
	row = row_at or row
	col = col_at or col
	vim.api.nvim_buf_set_text(self._.bufnr, row, col, row, col, { (" "):rep(n) })
	self:inc_pos(n, row)
end

---Add padding before line
---@param n integer
---@param row_at? integer
function Renderer:pad_before(n, row_at)
	self:pad(n, row_at, 0)
end

---Add padding before line
---@param n integer
---@param row_at? integer
function Renderer:pad_after(n, row_at)
	self:pad(n, row_at)
end

function Renderer:with_modifiable(fn)
	local bufnr = self._.bufnr
	if not (bufnr and vim.api.nvim_buf_is_valid(bufnr)) then
		return
	end

	local modifiable = vim.api.nvim_get_option_value("modifiable", { buf = bufnr })
	if not modifiable then
		utils.set_option_value("modifiable", true, { buf = bufnr })
		fn()
		utils.set_option_value("modifiable", false, { buf = bufnr })
	else
		fn()
	end
end

---@param element markup.Element
---@param state markup.Renderer.state
function Renderer:set_state(element, state)
	if not state.parent then
		state.box = { width = self:width(), height = self:height() }
	end

	self._.state[element] = vim.tbl_deep_extend("force", self._.state[element] or {}, state)
end

---@param element markup.Element
function Renderer:get_state(element)
	return self._.state[element]
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
