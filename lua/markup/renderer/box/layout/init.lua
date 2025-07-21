---@class markup.Render.Layout
---@field __name string
---@field __type table<markup.Render.LayoutType, boolean>
local Layout = {}

---@param name string
---@param type? markup.Render.LayoutType[]
function Layout.new(name, type)
	local type_lookup = {}
	for _, t in ipairs(type or {}) do
		type_lookup[t] = true
	end

	return {
		__name = name,
		__type = type_lookup,
	}
end

---@param box markup.Render.Box
function Layout.layout(box) ---@diagnostic disable-line: unused-local
	error("Layout.layout must be implemented by subclasses")
end

return Layout
