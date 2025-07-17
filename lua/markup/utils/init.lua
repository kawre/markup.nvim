local markup = require("markup.core")
local log = require("markup.logger") ---@diagnostic disable-line: unused-local

---@class markup.Utils
local utils = {}

function utils.set_option_value(name, value, opts)
	local ok, err = pcall(vim.api.nvim_set_option_value, name, value, opts)
	if not ok then
		log.error(err)
	end
end

function utils.buf_set_opts(bufnr, options)
	if vim.api.nvim_buf_is_valid(bufnr) then
		for opt, value in pairs(options) do
			utils.set_option_value(opt, value, { buf = bufnr })
		end
	end
end

function utils.win_set_opts(winid, options)
	if vim.api.nvim_win_is_valid(winid) then
		for opt, value in pairs(options) do
			utils.set_option_value(opt, value, { win = winid, scope = "local" })
		end
	end
end

function utils.starts_with(str, start)
	return str:sub(1, #start) == start
end

function utils.measure_time(name, fn)
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
function utils.is_instance(instance, class)
	return markup.Object.is_instance(instance, class)
end

---@param subclass any
---@param class any
function utils.is_subclass(subclass, class)
	return markup.Object.is_instance(subclass, class)
end

---@param class1 any
---@param class2 any
function utils.is_class(class1, class2)
	return markup.Object.is_class(class1, class2)
end

function utils.shallowcopy(orig)
	assert(type(orig) == "table", "`orig` must be a table")

	local copy = {}
	if vim.islist(orig) then
		for _, value in ipairs(orig) do
			table.insert(copy, value)
		end
	else
		for key, value in pairs(orig) do
			copy[key] = value
		end
	end

	return copy
end

function utils.index_of(tbl, value)
	for i, v in ipairs(tbl) do
		if v == value then
			return i
		end
	end
end

function utils.tbl_len(tbl)
	local count = 0
	for _ in pairs(tbl) do
		count = count + 1
	end
	return count
end

function utils.lookup(tbl, key, fn)
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
function utils.call_if_callable(value, ...)
	return vim.is_callable(value) and value(...) or value
end

math.randomseed(os.time())
local id_cache = {}

function utils.gen_id()
	local n = vim.loop.hrtime() + math.random(1e5, 1e6 - 1)
	local id = ("%x"):format(n % 0xFFFFFFF)
	if id_cache[id] then
		return utils.gen_id()
	else
		id_cache[id] = true
		return id
	end
end

return utils
