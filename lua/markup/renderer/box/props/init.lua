local defaults = require("markup.renderer.box.props.defaults")

---@alias markup.box.props.unit "auto" | "fit" | "full" | number

---@class markup.box.props
---@field margin_top integer
---@field margin_right integer
---@field margin_bottom integer
---@field margin_left integer
---@field padding_top integer
---@field padding_right integer
---@field padding_bottom integer
---@field padding_left integer
---@field width markup.box.props.unit
---@field height markup.box.props.unit
---@field min_width markup.box.props.unit
---@field min_height markup.box.props.unit
---@field max_width markup.box.props.unit
---@field max_height markup.box.props.unit
---@field spacing integer
---@field justify string
---@field align string
---@field basis string|integer
---@field vertical boolean
---@field sizing string
---@field reverse boolean
---@field style? markup.Element.style

local M = Markup.singleton()

---@param node markup.node
local function normalize_props(node)
	local props = node.props
	if not props then
		return {}
	end

	props = Markup.util.shallowcopy(props)
	props.children = nil

	if props.margin then
		local m = props.margin

		-- TODO margin_* values should have priority, unlike now
		if type(m) == "table" then
			local n = #m
			if n == 1 then
				props.margin_top = m[1]
				props.margin_right = m[1]
				props.margin_bottom = m[1]
				props.margin_left = m[1]
			elseif n == 2 then
				props.margin_top = m[1]
				props.margin_right = m[2]
				props.margin_bottom = m[1]
				props.margin_left = m[2]
			elseif n == 3 then
				props.margin_top = m[1]
				props.margin_right = m[2]
				props.margin_bottom = m[3]
				props.margin_left = m[2]
			elseif n ~= 0 then
				props.margin_top = m[1]
				props.margin_right = m[2]
				props.margin_bottom = m[3]
				props.margin_left = m[4]
			end
		elseif type(m) == "number" then
			props.margin_top = m
			props.margin_right = m
			props.margin_bottom = m
			props.margin_left = m
		end

		props.margin = nil
	end

	if props.padding then
		local p = props.padding

		if type(p) == "table" then
			local n = #p
			if n == 1 then
				props.padding_top = p[1]
				props.padding_right = p[1]
				props.padding_bottom = p[1]
				props.padding_left = p[1]
			elseif n == 2 then
				props.padding_top = p[1]
				props.padding_right = p[2]
				props.padding_bottom = p[1]
				props.padding_left = p[2]
			elseif n == 3 then
				props.padding_top = p[1]
				props.padding_right = p[2]
				props.padding_bottom = p[3]
				props.padding_left = p[2]
			elseif n ~= 0 then
				props.padding_top = p[1]
				props.padding_right = p[2]
				props.padding_bottom = p[3]
				props.padding_left = p[4]
			end
		elseif type(p) == "number" then
			props.padding_top = p
			props.padding_right = p
			props.padding_bottom = p
			props.padding_left = p
		end

		props.padding = nil
	end

	local key = node.tag_name
	return vim.tbl_extend("force", defaults.default, defaults[key] or {}, props)
end

---@param box markup.box
function M.call(box)
	local props = normalize_props(box.node)
	return props
	-- return setmetatable({}, {
	-- 	__index = function(_, key)
	-- 		local tag = box.node.tag_name
	-- 		local tag_defaults = defaults[tag]
	-- 		local prop = props[key]
	--
	-- 		if prop ~= nil then
	-- 			return prop
	-- 		elseif tag_defaults and tag_defaults[key] ~= nil then
	-- 			return tag_defaults[key]
	-- 		elseif defaults.default[key] ~= nil then
	-- 			return defaults.default[key]
	-- 		else
	-- 			error(string.format("Property `%s` not found for tag `%s`", key, tag))
	-- 		end
	-- 	end,
	-- })
end

return M
