local config = require("markup.config")

---@class markup.Assertor
local assertor = setmetatable({}, {
	__call = function(_, cond, message)
		assert(cond, message)
	end,
})

function assertor.bug(cond, message)
	if cond then
		return
	end

	local msg = table.concat({
		"\n" .. message .. ".",
		("This `error` is likely caused by a bug in `%s`."):format(config.name),
		"Please report this issue to the plugin maintainer.",
	}, "\n")
	error(msg)
end

function assertor.user(cond, message)
	if cond then
		return
	end

	local msg = table.concat({
		"\n" .. message .. ".",
		"This `error` is likely caused by an user.",
		("Please refer to `%s` documentation."):format(config.name),
	}, "\n")
	error(msg)
end

function assertor.hook_user(cond, message)
	if cond then
		return
	end

	local msg = table.concat({
		"\n" .. message .. ".",
		"This `error` is likely caused by an user.",
		("Please refer to `%s` hooks documentation."):format(config.name),
	}, "\n")
	error(msg)
end

return assertor
