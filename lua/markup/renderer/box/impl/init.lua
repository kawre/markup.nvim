---@class markup.box.impl
---@field compute_intrinsic_size fun(box: markup.box): markup.size
---@field layout fun(box: markup.box, input: markup.box.layout.Input)
---@field __name string
---@field __type table<markup.Render.LayoutType, boolean>
local M = Markup.singleton()

---@param name string
---@param type? markup.Render.LayoutType[]
function M.call(name, type)
	local type_lookup = {}
	for _, t in ipairs(type or {}) do
		type_lookup[t] = true
	end
	return {
		__name = name,
		__type = type_lookup,
	}
end

return M
