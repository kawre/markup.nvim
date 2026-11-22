---@class markup.util
local M = {}

local key_cache = {} ---@type table<string, string>
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
---@param groups table<string, string|vim.api.keyset.highlight> a link or a definition, by name
---@param opts? { prefix?:string, default?:boolean, managed?:boolean, ns?:integer }
function M.set_hl(groups, opts)
	opts = opts or {}
	for hl_group, hl in pairs(groups) do
		hl_group = opts.prefix and opts.prefix .. hl_group or hl_group
		hl = type(hl) == "string" and { link = hl } or hl --[[@as vim.api.keyset.highlight]]
		hl.default = opts.default
		if opts.managed ~= false then
			hl_groups[hl_group] = hl
		end
		vim.api.nvim_set_hl(opts.ns or 0, hl_group, hl)
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
		vim.api.nvim_set_option_value(k, v, { win = win, scope = "local" })
	end
end
--- Calls `fn` at once, and then at most once every `ms` while it keeps being
--- asked for, with the last ask always answered: for what fires many times in a
--- row, such as each step of dragging a window's edge.
---@param fn function
---@param ms integer
---@return function throttled
---@return function cancel
function M.throttle(fn, ms)
	local timer ---@type uv.uv_timer_t?
	local again = false

	local function stop()
		if timer and not timer:is_closing() then
			timer:stop()
			timer:close()
		end
		timer = nil
	end

	local function wait()
		timer = assert(vim.uv.new_timer())
		timer:start(ms, 0, function()
			vim.schedule(function()
				stop()
				if again then
					again = false
					fn()
					wait()
				end
			end)
		end)
	end

	return function()
		if timer then
			again = true
			return
		end
		fn()
		wait()
	end, stop
end

function M.benchmark(fn)
	local start_time = vim.uv.hrtime()
	fn()
	local end_time = vim.uv.hrtime()

	local elapsed = end_time - start_time -- ns
	return elapsed / 1e6 -- ms
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
function M.call(value, ...)
	return vim.is_callable(value) and value(...) or value
end

---@param str string
function M.keycode(str)
	return vim.api.nvim_replace_termcodes(str, true, true, true)
end

---@param key string
function M.normkey(key)
	if key_cache[key] then
		return key_cache[key]
	end
	local function norm(v)
		local l = v:lower()
		if l == "leader" then
			return M.normkey("<leader>")
		elseif l == "localleader" then
			return M.normkey("<localleader>")
		end
		return vim.fn.keytrans(M.keycode(("<%s>"):format(v)))
	end
	local orig = key
	key = key:gsub("<lt>", "<")
	local lower = key:lower()
	if lower == "<leader>" then
		key = vim.g.mapleader
		key = vim.fn.keytrans((not key or key == "") and "\\" or key)
	elseif lower == "<localleader>" then
		key = vim.g.maplocalleader
		key = vim.fn.keytrans((not key or key == "") and "\\" or key)
	else
		local extracted = {} ---@type string[]
		local function extract(v)
			v = v:sub(2, -2)
			if v:sub(2, 2) == "-" and v:sub(1, 1):find("[aAmMcCsS]") then
				local m = v:sub(1, 1):upper()
				m = m == "A" and "M" or m
				local k = v:sub(3)
				if #k > 1 then
					return norm(v)
				end
				if m == "C" then
					k = k:upper()
				elseif m == "S" then
					return k:upper()
				end
				return ("<%s-%s>"):format(m, k)
			end
			return norm(v)
		end
		local placeholder = "_#_"
		---@param v string
		key = key:gsub("(%b<>)", function(v)
			table.insert(extracted, extract(v))
			return placeholder
		end)
		key = vim.fn.keytrans(key):gsub("<lt>", "<")

		-- Restore extracted %b<> sequences
		local i = 0
		key = key:gsub(placeholder, function()
			i = i + 1
			return extracted[i] or ""
		end)
	end
	key_cache[orig] = key
	key_cache[key] = key
	return key
end

local transparent ---@type boolean?
--- Check if the colorscheme is transparent.
function M.is_transparent()
	if transparent == nil then
		transparent = M.color("Normal", "bg") == nil
		vim.api.nvim_create_autocmd("ColorScheme", {
			group = vim.api.nvim_create_augroup("snacks_util_transparent", { clear = true }),
			callback = function()
				transparent = nil
			end,
		})
	end
	return transparent
end

---@param fg string foreground color
---@param bg string background color
---@param alpha number number between 0 and 1. 0 results in bg, 1 results in fg
function M.blend(fg, bg, alpha)
	local bg_rgb =
		{ tonumber(bg:sub(2, 3), 16), tonumber(bg:sub(4, 5), 16), tonumber(bg:sub(6, 7), 16) }
	local fg_rgb =
		{ tonumber(fg:sub(2, 3), 16), tonumber(fg:sub(4, 5), 16), tonumber(fg:sub(6, 7), 16) }
	local blend = function(i)
		local ret = (alpha * fg_rgb[i] + ((1 - alpha) * bg_rgb[i]))
		return math.floor(math.min(math.max(0, ret), 255) + 0.5)
	end
	return string.format("#%02x%02x%02x", blend(1), blend(2), blend(3))
end

---@alias markup.object.type
---| "element"
---| "fiber"
---| "node"
---| "box"
---| "list"
---| "stack"

---@param obj table
---@param type markup.object.type
function M.typeof(obj, type)
	return getmetatable(obj).__type == "markup." .. type
end

return M
