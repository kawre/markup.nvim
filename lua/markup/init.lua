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
local M = {}
setmetatable(M, {
	__index = function(_, k)
		if not Markup.did_setup then
			M.setup()
		end
		return require("markup.lookup")[k]
	end,
})

_G.Markup = {
	debug_mode = false,
	debug = false,
	is_dev = false,
	did_setup = false,
	renderers = {},
}
-- _G.Markup = setmetatable({
-- 	debug_mode = false,
-- 	debug = false,
-- 	is_dev = false,
-- 	did_setup = false,
-- 	renderers = {},
-- }, {
-- 	__index = function(t, k)
-- 		t[k] = require("markup.core." .. k)
-- 		return rawget(t, k)
-- 	end,
-- })

---@param opts? table
function M.setup(opts)
	opts = opts or {}
	local config = require("markup.config")
	config.user = vim.tbl_deep_extend("force", config, opts)
	config.debug = opts.debug or config.debug
	Markup.is_dev = config.user.dev
	Markup.debug_mode = config.debug
	require("markup.theme").setup()

	Markup.util = require("markup.utils")
	Markup.log = require("markup.logger")
	Markup.debug = function(...)
		if Snacks then
			Snacks.debug(...)
		else
			Markup.log.debug(...)
		end
	end
	Markup.config = config

	local cmd = require("markup.cmd")
	cmd.setup()

	Markup.did_setup = true
end

-- require("markup-playground").setup()

return M
