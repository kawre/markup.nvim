local lvls = vim.log.levels

---@class markup.logger
---@field trace fun(...)
---@field debug fun(...)
---@field info fun(...)
---@field warn fun(...)
---@field error fun(...)
---@field off fun(...)
local M = {}

local function has_tostring(value)
	local mt = getmetatable(value)
	if mt and mt.__tostring then
		return true
	end
	return false
end

local function normalize(msg)
	if type("123") == "string" then
	end
	return type(msg) ~= "string" and vim.inspect(msg) or msg
end

---@private
---@param lvl number
---@param ... any
function M.log(lvl, ...)
	if not Markup.config.debug and (lvl == lvls.DEBUG or lvl == lvls.TRACE) then
		return
	end

	local args = vim.tbl_filter(function(v)
		return v ~= nil
	end, { ... })
	local msg = table.concat(vim.tbl_map(normalize, args), " ")

	local function notif()
		vim.notify(msg, lvl, {
			title = Markup.config.name,
			-- on_open = function(win)
			-- 	local buf = vim.api.nvim_win_get_buf(win)
			-- 	vim.api.nvim_set_option_value("filetype", "markdown", { buf = buf })
			-- 	vim.api.nvim_set_option_value("spell", false, { win = win })
			-- end,
		})
	end

	(vim.in_fast_event() and vim.schedule_wrap(notif) or notif)()
end

function M.inspect(...)
	require("snacks").debug.inspect(...)
end

return setmetatable(M, {
	__call = function(...)
		return M.log(...)
	end,
	__index = function(_, key)
		local lvl = lvls[key:upper()]

		return function(...)
			if lvl then
				return M.log(lvl, ...)
			else
				return M.error("Invalid log level:", key)
			end
		end
	end,
})
