local markup = require("markup.core")
local log = require("markup.logger") ---@diagnostic disable-line: unused-local

---@class markup.Utils
local M = {}

local hl_groups = {} ---@type table<string, vim.api.keyset.highlight>
vim.api.nvim_create_autocmd("ColorScheme", {
	group = vim.api.nvim_create_augroup("markup.util.hl", { clear = true }),
	callback = function()
		for hl_group, hl in pairs(hl_groups) do
			vim.api.nvim_set_hl(0, hl_group, hl)
		end
	end,
})

--- Ensures the hl groups are always set, even after a colorscheme change.
---@param groups snacks.util.hl
---@param opts? { prefix?:string, default?:boolean, managed?:boolean }
function M.set_hl(groups, opts)
	opts = opts or {}
	for hl_group, hl in pairs(groups) do
		hl_group = opts.prefix and opts.prefix .. hl_group or hl_group
		hl = type(hl) == "string" and { link = hl } or hl --[[@as vim.api.keyset.highlight]]
		hl.default = opts.default
		if opts.managed ~= false then
			hl_groups[hl_group] = hl
		end
		vim.api.nvim_set_hl(0, hl_group, hl)
	end
end

---@param group string|string[] hl group to get color from
---@param prop? string property to get. Defaults to "fg"
function M.color(group, prop)
	prop = prop or "fg"
	group = type(group) == "table" and group or { group }
	---@cast group string[]
	for _, g in ipairs(group) do
		local hl = vim.api.nvim_get_hl(0, { name = g, link = false })
		if hl[prop] then
			return string.format("#%06x", hl[prop])
		end
	end
end

function M.set_option_value(name, value, opts)
	local ok, err = pcall(vim.api.nvim_set_option_value, name, value, opts)
	if not ok then
		log.error(err)
	end
end

function M.buf_set_opts(bufnr, options)
	if vim.api.nvim_buf_is_valid(bufnr) then
		for opt, value in pairs(options) do
			M.set_option_value(opt, value, { buf = bufnr })
		end
	end
end

---Set buffer-local options.
---@param buf number
---@param bo vim.bo | table
function M.bo(buf, bo)
	for k, v in pairs(bo or {}) do
		vim.api.nvim_set_option_value(k, v, { buf = buf })
	end
end

---@param win number
---@param bo vim.bo | table
function M.wo(win, bo)
	for k, v in pairs(bo or {}) do
		vim.api.nvim_set_option_value(k, v, { win = win })
	end
end

function M.win_set_opts(winid, options)
	if vim.api.nvim_win_is_valid(winid) then
		for opt, value in pairs(options) do
			M.set_option_value(opt, value, { win = winid, scope = "local" })
		end
	end
end

function M.starts_with(str, start)
	return str:sub(1, #start) == start
end

function M.measure_time(name, fn)
	local start_time = vim.uv.hrtime()
	local res = fn()
	local end_time = vim.uv.hrtime()

	local elapsed = end_time - start_time
	local elapsed_ms, fps = elapsed / 1e6, math.floor(1e9 / elapsed)
	log.info(("[%s]: %.2f ms | %d fps"):format(name, elapsed_ms, fps))
	return res
end

---@param instance any
---@param class any
function M.is_instance(instance, class)
	return markup.Object.is_instance(instance, class)
end

---@param subclass any
---@param class any
function M.is_subclass(subclass, class)
	return markup.Object.is_instance(subclass, class)
end

---@param class1 any
---@param class2 any
function M.is_class(class1, class2)
	return markup.Object.is_class(class1, class2)
end

function M.shallowcopy(orig)
	assert(type(orig) == "table", "`orig` must be a table")

	local copy = {}
	-- if vim.islist(orig) then
	-- for _, value in ipairs(orig) do
	-- 	table.insert(copy, value)
	-- end
	-- else
	for key, value in pairs(orig) do
		copy[key] = value
	end
	-- end

	return copy
end

function M.index_of(tbl, value)
	for i, v in ipairs(tbl) do
		if v == value then
			return i
		end
	end
end

function M.tbl_len(tbl)
	local count = 0
	for _ in pairs(tbl) do
		count = count + 1
	end
	return count
end

function M.lookup(tbl, key, fn)
	local v = tbl[key:upper()]
	assert(v, ("lookup: key '%s' not found"):format(key))

	if type(v) == "function" then
		return v
	else
		return fn and fn(v) or require(v)
	end
end

---@param value any
---@param ...any function arguments
function M.call_if_callable(value, ...)
	return vim.is_callable(value) and value(...) or value
end

math.randomseed(os.time())
local id_cache = {}

function M.gen_id()
	local n = vim.loop.hrtime() + math.random(1e5, 1e6 - 1)
	local id = ("%x"):format(n % 0xFFFFFFF)
	if id_cache[id] then
		return M.gen_id()
	else
		id_cache[id] = true
		return id
	end
end

return M
