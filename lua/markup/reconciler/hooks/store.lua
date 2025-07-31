---@class markup.store
---@field observers table<markup.renderer, markup.fiber.hook[]>
---@field state table<string, any>
local M = Markup.object()

---@generic T
---@alias markup.hooks.store
---| fun(init: T): markup.store

function M:new(init)
	self.state = {}
	self.observers = {}

	local state_and_actions = init(function(updater)
		self:set(updater)
	end)
	for k, v in pairs(state_and_actions) do
		self.state[k] = v
	end
end

-- Returns the state table, modifing it will not reflect in window re-renders.
function M:get()
	return self.state
end

function M:set(updater)
	local new_state = updater(self.state)
	local did_update = false

	for k, v in pairs(new_state or {}) do
		if self.state[k] ~= v then
			self.state[k] = v
			did_update = true
		end
	end

	if did_update then
		for observer, hooks in pairs(self.observers) do
			for _, hook in ipairs(hooks) do
				hook.need_update = true
			end
			observer:schedule_rerender()
		end
	end
end

function M:read()
	local fiber = Markup.reconciler.current_fiber
	Markup.assert.user(fiber, "No current fiber") ---@cast fiber -nil

	if not fiber.alternate then
		self:mount_store(fiber)
	else
		self:update_store(fiber)
	end

	return self.state
end

function M:mount_store(fiber)
	local renderer = Markup.renderer.current
	Markup.assert.user(renderer, "Store must be mounted within a renderer context") ---@cast renderer -nil

	local hook = Markup.reconciler.mount_wip_hook({
		memoized_state = self,
		need_update = false,
	})

	Markup.assert.user(
		self.observers[renderer],
		"Store must be bound to a renderer before mounting"
	)
	table.insert(self.observers[renderer], hook)
end

function M:update_store()
	Markup.reconciler.update_wip_hook()
end

---@param renderer markup.renderer
function M:bind(renderer)
	self.observers[renderer] = {}
end

---@param renderer markup.renderer
function M:unbind(renderer)
	self.observers[renderer] = nil
end

return M
