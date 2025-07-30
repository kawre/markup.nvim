local M = Markup.object()

---@alias markup.hooks.store
---| fun(init: fun(set: fun(updater: fun(state: table): table)): table)

function M.store:new(init)
	self.store = {}

	local set = function(updater)
		local new_state = updater(self.store)
		local did_update = false
		for k, v in pairs(new_state) do
			if self.store[k] ~= v then
				self.store[k] = v
				did_update = true
			end
		end
		if did_update then
			for _, observer in ipairs(self.observers) do
				observer:schedule_rerender()
			end
		end
	end

	local state_and_actions = init(set)
	for k, v in pairs(state_and_actions) do
		self.store[k] = v
	end
end

---@param renderer markup.renderer
function M.store:bind(renderer)
	table.insert(self.observers, renderer)
end

---@param renderer markup.renderer
function M.store:unbind(renderer)
	for i, observer in ipairs(self.observers) do
		if observer == renderer then
			table.remove(self.observers, i)
			return
		end
	end
end

return M
