local Tag = require("markup.reconciler.enum").Tag

---@class markup.hooks.context.dep
---@field ctx markup.hooks.context
---@field memoized_value any
---@field next markup.hooks.context.dep?

---@class markup.hooks.context
---@field current any
---@field typeof string
---@overload fun(default): markup.hooks.context
local M = Markup.object()

---@param default any
function M:new(default)
	self.typeof = Tag.CONTEXT
	self.current = default
end

function M:provider(...)
	return Markup.factory.element(self, ...)
end

function M:read_for_consumer(consumer)
	local value = self.current

	---@type markup.hooks.context.dep
	local ctx_dep = { ctx = self, memoized_value = value, next = nil }

	if not Markup.reconciler.last_context_dep then
		Markup.reconciler.last_context_dep = ctx_dep
		consumer.deps = { first_context = ctx_dep }
	else
		Markup.reconciler.last_context_dep.next = ctx_dep
		Markup.reconciler.last_context_dep = ctx_dep
	end

	return value
end

function M:read()
	local fiber = Markup.reconciler.current_fiber
	assert(fiber, "Cannot read context outside of a fiber")
	return self:read_for_consumer(fiber)
end

return M
