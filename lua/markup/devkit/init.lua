---@class markup.devkit
local M = {}

M.visualizer = require("markup.devkit.visualizer")
M.inspect = require("markup.devkit.inspect")

--- Inspector for views. Loaded on first use, because it needs the native core.
---@return markup.devkit.tree
function M.tree()
	return require("markup.devkit.tree")
end

return M
