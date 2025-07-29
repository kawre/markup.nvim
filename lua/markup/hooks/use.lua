local Tag = require("markup.reconciler.enum").Tag
local Context = require("markup.reconciler.hook.context")

---@alias markup.hooks.use function

local function use(spec)
	if spec.typeof == Tag.CONTEXT then
		---@cast spec markup.hooks.context
		return Context.read(spec)
	end
end

return use
