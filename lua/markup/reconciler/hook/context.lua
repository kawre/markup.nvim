---@generic T
---@alias markup.context
---| fun(initial_state: T): T, fun(value: T | fun(value: T): T?)

local function context()
	local fiber = Markup.reconciler.static.get_currently_rendering_fiber(true)
	assert(fiber, "context hook must be called within a fiber")

	local ctx = Markup.object()
	function ctx:new()
		self.provider = function(...)
			return Markup.factory.element("context", ...)
		end
	end
	return ctx
end

return context
