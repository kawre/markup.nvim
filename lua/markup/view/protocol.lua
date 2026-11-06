--- Lua half of the wire format described in `core/engine/protocol.rs`.
---
--- Commands go into one flat array that is sent once per frame. Appending to a
--- table keeps the hot path inside LuaJIT, and node ids are chosen here so no
--- command needs a reply.

---@class markup.view.protocol
local M = {}

local OP = {
	create = 1,
	create_text = 2,
	set_text = 3,
	set_style = 4,
	insert = 5,
	remove = 6,
	clear = 7,
	resize = 8,
}

M.display = { block = 1, inline = 2, contents = 3 }

M.ROOT = 1

local LENGTH = { auto = -1, fit = -2, full = -3 }

local function length(value)
	return LENGTH[value] or value
end

local function number(value)
	return value
end

local function flag(value)
	return value and 1 or 0
end

--- Style properties by name, with the encoder for each value.
M.style = {
	margin_top = { 1, number },
	margin_right = { 2, number },
	margin_bottom = { 3, number },
	margin_left = { 4, number },
	padding_top = { 5, number },
	padding_right = { 6, number },
	padding_bottom = { 7, number },
	padding_left = { 8, number },
	width = { 9, length },
	height = { 10, length },
	spacing = { 11, number },
	reverse = { 12, flag },
	hl = { 13, number },
	interactive = { 14, flag },
}

local vim_fn = vim.fn

--- Width of a text, or -1 when the engine can use its byte length. Neovim
--- measures everything else, so `ambiwidth` and `setcellwidths()` are honoured.
local function text_width(text)
	if text:find("[\128-\255]") then
		return vim_fn.strdisplaywidth(text)
	end
	return -1
end

---@class markup.view.commands
---@field ops any[]
---@field len integer
local Commands = {}
Commands.__index = Commands

---@return markup.view.commands
function M.commands()
	return setmetatable({ ops = {}, len = 0 }, Commands)
end

function Commands:create(id, display)
	local ops, n = self.ops, self.len
	ops[n + 1], ops[n + 2], ops[n + 3] = OP.create, id, display
	self.len = n + 3
end

function Commands:create_text(id, text)
	local ops, n = self.ops, self.len
	ops[n + 1], ops[n + 2], ops[n + 3], ops[n + 4] = OP.create_text, id, text, text_width(text)
	self.len = n + 4
end

function Commands:set_text(id, text)
	local ops, n = self.ops, self.len
	ops[n + 1], ops[n + 2], ops[n + 3], ops[n + 4] = OP.set_text, id, text, text_width(text)
	self.len = n + 4
end

---@param name string
---@param value any
function Commands:set_style(id, name, value)
	local property = M.style[name]
	local ops, n = self.ops, self.len
	ops[n + 1], ops[n + 2], ops[n + 3], ops[n + 4] = OP.set_style, id, property[1], property[2](value)
	self.len = n + 4
end

---@param before? integer
function Commands:insert(parent, child, before)
	local ops, n = self.ops, self.len
	ops[n + 1], ops[n + 2], ops[n + 3], ops[n + 4] = OP.insert, parent, child, before or 0
	self.len = n + 4
end

function Commands:remove(id)
	local ops, n = self.ops, self.len
	ops[n + 1], ops[n + 2] = OP.remove, id
	self.len = n + 2
end

function Commands:clear(id)
	local ops, n = self.ops, self.len
	ops[n + 1], ops[n + 2] = OP.clear, id
	self.len = n + 2
end

function Commands:resize(width)
	local ops, n = self.ops, self.len
	ops[n + 1], ops[n + 2] = OP.resize, width
	self.len = n + 2
end

return M
