---@class markup
---@field inline markup.factory.Element.constructor
---@field block markup.factory.Element.constructor
---@field flex markup.factory.Element.constructor
---@field grid markup.factory.Element.constructor
---@field element markup.factory.Element.constructor.raw
---@field variable markup.use_state
---@field [string] markup.factory.Element.constructor
local M = {}

---@class markup.global
---@field collection markup.collection
---@field assert markup.assert
---@field log markup.logger
---@field util markup.util
---@field devkit markup.devkit
---@field config markup.config
---@field playground markup.playground
---@field core markup.core
---@field cmd markup.cmd
---@field factory markup.factory
---@field window markup.window
---@field renderer markup.renderer
---@field reconciler markup.reconciler
---@field object markup.object
_G.Markup = setmetatable({
	core = M,
	debug = function(...)
		return Markup.log.debug(...)
	end,
}, {
	__index = function(t, k)
		t[k] = require("markup." .. k)
		return rawget(t, k)
	end,
})

M.Component = Markup.factory.element.component
M.Class = Markup.factory.element.class
M.Fragment = Markup.factory.element.fragment
M.variable = require("markup.reconciler.hook.state")
-- M.For = function(items, fn)
-- 	Markup.log.info(items)
-- 	return vim.tbl_map(fn, items)
-- end
setmetatable(M, {
	__call = function(_, ...)
		return Markup.factory.element(...)
	end,
	__index = function(_, k)
		return function(...)
			return Markup.factory.element(k:lower(), ...)
		end
	end,
})

---@private
---@param opts? table
function M.setup(opts)
	Markup.config.merge(opts)
	Markup.cmd.setup()
end

return M
