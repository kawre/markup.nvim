--- The colors a user would see in each cell of a child Neovim.
---
--- Attaches to the child as a real UI, the way a terminal or GUI does, and
--- keeps its screen from the `redraw` events. Without `ext_multigrid` Neovim
--- sends the screen composed: floats over windows, `winblend` and backdrops
--- mixed in, highlight namespaces and `winhighlight` applied. What is left is
--- the final RGB of every cell, which does not depend on how a version of
--- Neovim numbers its highlights internally.
---
--- ```lua
--- local Screen = dofile("tests/helpers/screen.lua")
--- local screen = Screen.attach(child)
--- child.lua([[ ... ]])
--- screen:update()
--- eq(screen:cell(1, 1).fg, "#cdd6f4")
--- eq(screen:spans(1), { { "one", fg = "#cdd6f4", bg = "#1e1e2e" }, ... })
--- ```

---@class tests.Cell
---@field text string
---@field fg? string `#rrggbb`, nil when the UI default is unset
---@field bg? string nil on a transparent background, where the terminal shows its own
---@field sp? string
---@field bold? true
---@field italic? true
---@field underline? true
---@field undercurl? true
---@field strikethrough? true

---@class tests.Screen
---@field private pipe uv.uv_pipe_t
---@field private unpack fun(data: string, pos: integer): any, integer
---@field private msgid integer
---@field private responses table<integer, table>
---@field private grid { text: string, hl: integer }[][]
---@field private attrs table<integer, table>
---@field private default { fg?: integer, bg?: integer, sp?: integer }
---@field private closed boolean
---@field width integer
---@field height integer
local Screen = {}
Screen.__index = Screen

local STYLES = { "bold", "italic", "underline", "undercurl", "strikethrough" }

local function hex(color)
	if color == nil or color < 0 then
		return nil
	end
	return ("#%06x"):format(color)
end

--- Attaches to a running child of `MiniTest.new_child_neovim()`, at the size
--- of its editor unless given one.
---@param child table
---@param opts? { width?: integer, height?: integer }
---@return tests.Screen
function Screen.attach(child, opts)
	opts = opts or {}
	local self = setmetatable({
		width = opts.width or child.o.columns,
		height = opts.height or child.o.lines,
		msgid = 0,
		responses = {},
		attrs = { [0] = {} },
		default = {},
		closed = false,
		unpack = vim.mpack.Unpacker(),
	}, Screen)
	self:resize_grid(self.width, self.height)

	local pipe = assert(vim.uv.new_pipe(false))
	self.pipe = pipe
	local connected, err
	pipe:connect(child.job.address, function(e)
		err, connected = e, true
	end)
	assert(
		vim.wait(5000, function()
			return connected
		end, 5),
		"screen: no connection to the child"
	)
	assert(not err, err)

	pipe:read_start(function(read_err, data)
		if read_err or not data then
			self.closed = true
			return
		end
		self:receive(data)
	end)

	self:request("nvim_ui_attach", self.width, self.height, { rgb = true, ext_linegrid = true })
	self:update()
	return self
end

function Screen:detach()
	if self.closed then
		return
	end
	self.closed = true
	pcall(function()
		self.pipe:read_stop()
		self.pipe:close()
	end)
end

---@private
function Screen:resize_grid(width, height)
	self.width, self.height = width, height
	self.grid = {}
	for row = 1, height do
		local line = {}
		for col = 1, width do
			line[col] = { text = " ", hl = 0 }
		end
		self.grid[row] = line
	end
end

---@private
function Screen:request(method, ...)
	self.msgid = self.msgid + 1
	local id = self.msgid
	self.pipe:write(vim.mpack.encode({ 0, id, method, { ... } }))
	assert(
		vim.wait(5000, function()
			return self.responses[id] ~= nil or self.closed
		end, 1),
		"screen: no answer to " .. method
	)
	local response = self.responses[id]
	self.responses[id] = nil
	assert(response, "screen: the child went away")
	if response[3] ~= nil and response[3] ~= vim.NIL then
		error(("screen: %s failed: %s"):format(method, vim.inspect(response[3])))
	end
	return response[4]
end

---@private
function Screen:receive(data)
	local pos = 1
	while pos <= #data do
		local message
		message, pos = self.unpack(data, pos)
		if message == nil then
			break
		end
		if message[1] == 1 then
			self.responses[message[2]] = message
		elseif message[1] == 2 and message[2] == "redraw" then
			for _, event in ipairs(message[3]) do
				local handler = self["on_" .. event[1]]
				if handler then
					for i = 2, #event do
						handler(self, unpack(event[i]))
					end
				end
			end
		end
	end
end

---@private
function Screen:on_grid_resize(grid, width, height)
	if grid == 1 then
		self:resize_grid(width, height)
	end
end

---@private
function Screen:on_default_colors_set(fg, bg, sp)
	self.default = { fg = fg, bg = bg, sp = sp }
end

---@private
function Screen:on_hl_attr_define(id, rgb)
	self.attrs[id] = rgb
end

---@private
function Screen:on_grid_clear(grid)
	if grid == 1 then
		self:resize_grid(self.width, self.height)
	end
end

---@private
function Screen:on_grid_line(grid, row, col, cells)
	if grid ~= 1 then
		return
	end
	local line = self.grid[row + 1]
	if not line then
		return
	end
	local hl = 0
	col = col + 1
	for _, cell in ipairs(cells) do
		local text, id, count = cell[1], cell[2], cell[3] or 1
		if id ~= nil and id ~= vim.NIL then
			hl = id
		end
		for _ = 1, count do
			if line[col] then
				line[col] = { text = text, hl = hl }
			end
			col = col + 1
		end
	end
end

---@private
function Screen:on_grid_scroll(grid, top, bot, left, right, rows)
	if grid ~= 1 then
		return
	end
	-- Rows [top, bot) and columns [left, right) move up by `rows`, or down
	-- when it is negative. What they leave behind is redrawn by grid_line.
	local from, to, step = top, bot - 1, 1
	if rows < 0 then
		from, to, step = bot - 1, top, -1
	end
	for row = from, to, step do
		local source = row + rows
		if source >= top and source < bot then
			for col = left + 1, right do
				self.grid[row + 1][col] = self.grid[source + 1][col]
			end
		end
	end
end

--- Waits until the child has drawn everything it was asked to, and the screen
--- here has all of it.
---@param child? table redraws it first when given
function Screen:update(child)
	if child then
		child.cmd("redraw")
	end
	-- Answered after everything the child wrote to this UI before it.
	local normal = self:request("nvim_get_hl", 0, { name = "Normal" })
	-- The UI is told a background even when `Normal` has none, black on a
	-- dark one. A terminal shows its own there instead.
	self.transparent = normal.bg == nil
end

--- The cell at a row and column of the screen, both from 1.
---@return tests.Cell
function Screen:cell(row, col)
	local cell =
		assert(self.grid[row] and self.grid[row][col], ("screen: no cell %d,%d"):format(row, col))
	local attr = self.attrs[cell.hl] or {}
	local fg = attr.foreground or self.default.fg
	local bg = attr.background or (not self.transparent and self.default.bg or nil)
	if attr.reverse then
		fg, bg = bg, fg
	end
	local result = { text = cell.text, fg = hex(fg), bg = hex(bg), sp = hex(attr.special) }
	for _, style in ipairs(STYLES) do
		if attr[style] then
			result[style] = true
		end
	end
	return result
end

--- The text of a row, the way the screen shows it.
function Screen:line(row)
	local parts = {}
	for col = 1, self.width do
		parts[#parts + 1] = self.grid[row][col].text
	end
	return table.concat(parts)
end

local function same_look(a, b)
	if a.fg ~= b.fg or a.bg ~= b.bg or a.sp ~= b.sp then
		return false
	end
	for _, style in ipairs(STYLES) do
		if a[style] ~= b[style] then
			return false
		end
	end
	return true
end

--- A row as runs of cells that look the same: `{ text, fg = ..., bg = ... }`.
--- Columns `from` to `to` (from 1, inclusive), the whole row by default.
---@return table[]
function Screen:spans(row, from, to)
	local spans = {}
	for col = from or 1, to or self.width do
		local cell = self:cell(row, col)
		local last = spans[#spans]
		if last and same_look(last, cell) then
			last[1] = last[1] .. cell.text
		else
			cell[1], cell.text = cell.text, nil
			spans[#spans + 1] = cell
		end
	end
	return spans
end

--- Where `text` first is on the screen, as row and column from 1.
---@return integer? row, integer? col
function Screen:find(text)
	for row = 1, self.height do
		local cols, line = {}, ""
		for col = 1, self.width do
			cols[#line + 1] = col
			line = line .. self.grid[row][col].text
		end
		local at = line:find(text, 1, true)
		if at then
			return row, cols[at]
		end
	end
end

--- The look of the cell where `text` starts.
---@return tests.Cell
function Screen:cell_at(text)
	local row, col = self:find(text)
	assert(row, ("screen: %q is not on the screen"):format(text))
	---@cast col integer
	return self:cell(row, col)
end

return Screen
