---@class markup.config
local M = {
	user = {
		logging = true,
		animate = {
			--- The most frames a second animations move at, `math.huge` for no cap.
			--- Match it to the display, such as 60, 120 or 180.
			fps = 60,
			--- Tick only when an animation can change, so `fps` is a ceiling
			--- rather than a constant rate.
			vrr = true,
		},
		--- Defaults for the inspector's options, which `s` in the inspector
		--- changes while it is open.
		inspector = {
			follow = true, -- select the element under the view's cursor
			show_groups = false, -- list the invisible nodes components wrap their content in
			mark = true, -- mark the selected element inside the view itself
			geometry = true, -- position and size on every row
			hl_names = true, -- highlight groups on every row
			guides = true, -- lines joining nested elements
			live = true, -- refresh the tree as the view changes
		},
	},
	name = "markup.nvim",
	--- The version of markup.nvim. release-please sets it with the one in
	--- Cargo.toml, which the engine reports as `require("markup.core").version`.
	version = "0.8.0", -- x-release-please-version
	--- The oldest Neovim markup.nvim supports. CI tests every release from it up.
	min_nvim = "0.10.0",
	debug = false,
}

--- Whether the installed markup.nvim release satisfies a vim.version.range spec.
--- Can be called before loading the UI or the native engine.
---@param spec string
---@return boolean
function M.supports(spec)
	local range = vim.version.range(spec)
	return range ~= nil and range:has(M.version)
end

local is_dict_like = function(v) -- has string and number keys
	return type(v) == "table" and (vim.tbl_isempty(v) or not vim.islist(v))
end
local is_dict = function(v) -- has only string keys
	return type(v) == "table" and (vim.tbl_isempty(v) or not v[1])
end

--- Merges the values similar to vim.tbl_deep_extend with the **force** behavior,
--- but the values can be any type
---@generic T
---@param ... T
---@return T
function M.merge(...)
	local ret = select(1, ...)
	for i = 2, select("#", ...) do
		local value = select(i, ...)
		if is_dict_like(ret) and is_dict(value) then
			for k, v in pairs(value) do
				ret[k] = M.merge(ret[k], v)
			end
		elseif value ~= nil then
			ret = value
		end
	end
	return ret
end

return M
