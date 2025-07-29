local Tag = require("markup.reconciler.enum").Tag

---@class markup.hooks.context.dep
---@field ctx markup.hooks.context
---@field memoized_value any
---@field next markup.hooks.context.dep?

---@class markup.hooks.context
local M = Markup.singleton()

function M.read_for_consumer(consumer, ctx)
	local value = ctx.current
	local ctx_dep = { ctx = ctx, memoized_value = value, next = nil }

	if not Markup.reconciler.last_context_dep then
		Markup.reconciler.last_context_dep = ctx_dep
		consumer.deps = {
			first_context = ctx_dep,
		}
	else
		Markup.reconciler.last_context_dep.next = ctx_dep
		Markup.reconciler.last_context_dep = ctx_dep
	end

	return value
end

function M.read(ctx)
	local fiber = Markup.reconciler.current_fiber
	return M.read_for_consumer(fiber, ctx)
end

return M
