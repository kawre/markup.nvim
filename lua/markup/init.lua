local log = require("markup.logger") ---@diagnostic disable-line: unused-local
local enum = require("markup.enum")

---@class markup
---@field core markup.core
local markup = enum:bind()

---@param opts? table
function markup.setup(opts)
	opts = opts or {}
	local config = require("markup.config")
	config.user = vim.tbl_deep_extend("force", config, opts)
	config.debug = opts.debug or config.debug
end

require("markup-playground").setup()
require("markup.theme").setup()

return markup
