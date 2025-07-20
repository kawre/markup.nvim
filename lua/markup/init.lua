local log = require("markup.logger") ---@diagnostic disable-line: unused-local
local lookup = require("markup.lookup")
local cmd = require("markup.cmd")

_Markup = { renderers = {}, is_dev = false, debug_mode = false }

---@class markup
---@field inline markup.factory.Element.constructor
---@field block markup.factory.Element.constructor
---@field flex markup.factory.Element.constructor
---@field grid markup.factory.Element.constructor
---@field element markup.factory.Element.constructor.raw
---@field Component fun(...)
---@field Class { render: fun(...) }
---@field Fragment markup.factory.Element.Fragment.constructor
---@field For fun(items, fn): table
---@field variable markup.use_state
---@field Window any
---@field Renderer any
---@field [string] markup.factory.Element.constructor
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
	_Markup.is_dev = config.user.dev
	_Markup.debug_mode = config.debug
	require("markup.theme").setup()
	cmd.setup()
end

-- require("markup-playground").setup()

return markup
