local log = require("markup.logger") ---@diagnostic disable-line: unused-local
local lookup = require("markup.lookup")

---@class markup
---@field inline markup.factory.Element.constructor
---@field block markup.factory.Element.constructor
---@field flex markup.factory.Element.constructor
---@field grid markup.factory.Element.constructor
---@field element markup.factory.Element.constructor.raw
---@field Component markup.factory.Element.constructor
---@field Class markup.factory.Element.constructor
---@field Fragment markup.factory.Element.constructor
---@field [string] markup.factory.Element.constructor
---@field Window any
---@field Renderer any
local markup = {}
setmetatable(markup, {
	__index = function(_, k)
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
