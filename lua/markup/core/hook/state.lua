local markup = require("markup.core")

local log = require("markup.logger") ---@diagnostic disable-line: unused-local
local FiberFlag = require("markup.core.reconciler.enum").Flag

---@generic T
---@alias markup.use_state
---| fun(initial_state: T): T, fun(value: T | fun(value: T): T?)

---@type markup.use_state
local function use_state(initial)
	local fiber = markup.Reconciler.static.get_currently_rendering_fiber()
	assert(fiber, "`use_state` must be called inside a fiber, this is a bug.")

	if not fiber.memoized_state then
		fiber.memoized_state = { value = initial }
	end

	local function set_state(new_state)
		if type(new_state) == "function" then
			new_state = new_state(fiber.memoized_state.value)
		end

		if not vim.deep_equal(fiber.memoized_state.value, new_state) then
			fiber.memoized_state.value = new_state
			fiber.flag = FiberFlag.UPDATE
		end
	end

	return fiber.memoized_state.value, set_state
end

return use_state
