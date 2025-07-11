local log = require("markup.logger") ---@diagnostic disable-line: unused-local
local lookup = require("markup.lookup")

---@class markup: markup.lookup
local markup = {}
setmetatable(markup, {
	__index = function(_, k)
		---@diagnostic disable-next-line: no-unknown
		return lookup[k]
	end,
})

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
