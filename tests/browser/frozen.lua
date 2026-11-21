--- The static tree used to reproduce and reduce a captured fuzz state.
local m = require("markup")
local M = {}

function M.freeze(world)
	local function val(knob)
		return world.knobs[knob].signal()
	end

	local function freeze(spec, item)
		local k = spec.kind
		if k == "text" then
			return { kind = "text", value = spec.value .. (item and ("#" .. item) or "") }
		elseif k == "dyntext" then
			return { kind = "text", value = val(spec.knob) .. (item and ("#" .. item) or "") }
		elseif k == "dynchild" then
			return val(spec.knob) and freeze(spec.child, item)
				or { kind = "text", value = spec.text }
		elseif k == "show" then
			if val(spec.knob) then
				return freeze(spec.child, item)
			end
			return spec.fallback and freeze(spec.fallback, item) or { kind = "none" }
		elseif k == "collapse" then
			return { kind = "collapse", open = val(spec.knob), child = freeze(spec.child, item) }
		elseif k == "each" then
			local items = {}
			for _, key in ipairs(val(spec.knob)) do
				items[#items + 1] = {
					kind = "box",
					tag = "block",
					props = {},
					children = {
						{ kind = "text", value = "item " .. key .. " " },
						freeze(spec.item, key),
					},
				}
			end
			return { kind = "box", tag = "block", props = {}, children = items }
		elseif k == "slide" then
			local page = val(spec.knob)
			return {
				kind = "slide",
				page = page,
				child = {
					kind = "box",
					tag = "block",
					props = {},
					children = {
						{ kind = "text", value = "page " .. page },
						freeze(spec.pages[page], item),
					},
				},
			}
		elseif k == "component" then
			return freeze(spec.child, item)
		end
		local props = vim.deepcopy(spec.props)
		for name, index in pairs(spec.dynamic) do
			props[name] = val(index)
		end
		local children = {}
		for _, c in ipairs(spec.children) do
			children[#children + 1] = freeze(c, item)
		end
		return { kind = "box", tag = spec.tag, props = props, children = children }
	end
	return freeze(world.root)
end

function M.build(spec)
	local k = spec.kind
	if k == "none" then
		return nil
	elseif k == "text" then
		return spec.value
	elseif k == "collapse" then
		return m.collapse(function()
			return spec.open
		end, function()
			return m.block({ M.build(spec.child) })
		end)
	elseif k == "slide" then
		return m.slide(function()
			return 1
		end, function()
			return M.build(spec.child)
		end)
	end
	local props = vim.deepcopy(spec.props)
	local children = {}
	for _, c in ipairs(spec.children) do
		local b = M.build(c)
		if b ~= nil then
			children[#children + 1] = b
		end
	end
	props.children = children
	return m[spec.tag](props)
end

return M
