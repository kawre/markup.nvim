local config = require("markup.config")

---@class markup.assert
local M = setmetatable({}, {
	__call = function(_, cond, message)
		assert(cond, message)
	end,
})

function M.bug(cond, message)
	if cond then
		return
	end
	local msg = string.format(
		"%s. This `error` is likely caused by a bug in `%s`. Please report this issue to the plugin maintainer.",
		message,
		config.name
	)
	error(msg)
end

function M.user(cond, message)
	if cond then
		return
	end
	-- local msg = table.concat({
	-- 	message .. ".",
	-- 	"This `error` is likely caused by an user.",
	-- 	("Please refer to `%s` documentation."):format(config.name),
	-- }, " ")
	local msg = string.format(
		"%s. This `error` is likely caused by an user. Please refer to `%s` documentation.",
		message,
		config.name
	)
	error(msg)
end

function M.hook_user(cond, message)
	if cond then
		return
	end
	local msg = table.concat({
		message .. ".",
		"This `error` is likely caused by an user.",
		("Please refer to `%s` hooks documentation."):format(config.name),
	}, " ")
	error(msg)
end

return M
