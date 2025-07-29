local Tag = require("markup.reconciler.enum").Tag
local ctx = require("markup.hooks.context")

---@alias markup.hooks.use function

local function use(spec)
	if spec.typeof == Tag.CONTEXT then
		---@cast spec markup.hooks.context
		return ctx.read(spec)
	end
end

return use
