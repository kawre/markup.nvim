---@class markup.Render.Layout
---@field __name string
---@field __type table<markup.Render.LayoutType, boolean>
local M = {}

---@param name string
---@param type? markup.Render.LayoutType[]
function M.new(name, type)
	local type_lookup = {}
	for _, t in ipairs(type or {}) do
		type_lookup[t] = true
	end

	return {
		__name = name,
		__type = type_lookup,
	}
end

---@param box markup.box
---@param constraints? markup.box.constraints
function M.layout(box, constraints) ---@diagnostic disable-line: unused-local
	error("Layout.layout must be implemented by subclasses")
end

---@class markup.box.constraints
---@field width? number
---@field height? number
---@field min_width? number
---@field min_height? number
---@field max_width? number
---@field max_height? number

---@param size number
---@param ref number
function M.resolve_size(size, ref)
	if size < 1 then
		return math.floor(ref * size)
	else
		return math.floor(size)
	end
end

return M
