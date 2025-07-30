local config = require("markup.config")

---@class markup.assert
local M = {}

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
		Markup.config.name
	)
	error(msg)
end

function M.user_hook(cond)
	M.user(cond, "You are likely calling Hooks conditionally, which is not allowed")
end

return M
