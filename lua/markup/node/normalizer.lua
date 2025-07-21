---@class markup.Node.Normalizer
local M = {}

---@param props markup.Node.props
function M.props(props)
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

	return props
end

return M
