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

---@param box markup.Render.Box
function Layout.apply_size_constraints(box) ---@diagnostic disable-line: unused-local
	local width = box.props.width
	local parent_cbox = box.parent:content_box_size()

	local new_width = 0
	if width > 0 then
		if width < 1 then
			new_width = math.ceil(parent_cbox.width * width)
		else
			new_width = width
		end
	else
		new_width = parent_cbox.width
	end

	box:set_content_box_size(new_width, parent_cbox.height)
end

return Layout
