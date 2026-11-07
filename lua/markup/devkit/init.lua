---@class markup.devkit
local M = {}

--- The inspector. Loaded on first use, because it needs the native core.
---@return markup.devkit.tree
function M.tree()
	return require("markup.devkit.tree")
end

--- Toggles the inspector for the view in the current window or tab.
function M.inspect()
	local view = Markup.view.find()
	if view then
		M.tree().toggle(view)
	else
		Markup.log.warn("No view to inspect")
	end
end

return M
