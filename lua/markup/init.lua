local log = require("markup.logger") ---@diagnostic disable-line: unused-local
local enum_core = require("markup.core.enum")
local enum = require("markup.enum")

---@class markup
local markup = enum.bind(enum.Lookup)
markup.core = enum.bind(enum_core.Lookup)

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
