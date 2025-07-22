local Tag = require("markup.reconciler.enum").Tag

---@class markup.hooks.context
local M = Markup.singleton()

function M.read_for_consumer(consumer, ctx)
	local value = ctx.current
	local ctx_dep = { ctx = ctx, memoized_value = value, next = nil }

	if not Markup.reconciler.static.last_context_dep then
		Markup.reconciler.static.last_context_dep = ctx_dep
		consumer.deps = {
			first_context = ctx_dep,
		}
	else
		Markup.reconciler.static.last_context_dep.next = ctx_dep
		Markup.reconciler.static.last_context_dep = ctx_dep
	end

	return value
end

function M.read(ctx)
	local fiber = Markup.reconciler.static.get_currently_rendering_fiber(true)
	return M.read_for_consumer(fiber, ctx)
end

return M
