local Tag = require("markup.reconciler.enum").Tag

local M = Markup.singleton()

---@generic T
---@alias markup.hooks.use fun(hook: T): T

function M.call(hook)
	return hook:read()
	-- if hook.typeof == Tag.CONTEXT then
	-- 	---@cast hook markup.hooks.context
	-- 	return hook:read()
	-- end
end

return M
