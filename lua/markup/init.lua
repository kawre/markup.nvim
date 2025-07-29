---@class markup
---@field inline markup.factory.Element.constructor
---@field block markup.factory.Element.constructor
---@field flex markup.factory.Element.constructor
---@field grid markup.factory.Element.constructor
---@field element markup.factory.Element.constructor.raw
---@field variable markup.use_state
---@field effect markup.effect
---@field ref markup.ref
---@field private setup any
---@field [string] markup.factory.Element.constructor
local M = {}

---@class markup.global
---@field core markup
---@field collection markup.collection
---@field log markup.logger
---@field util markup.util
---@field devkit markup.devkit
---@field playground markup.playground
---@field factory markup.factory
---@field dispatcher markup.dispatcher
---@field window markup.window
---@field renderer markup.renderer
---@field assert markup.assert
---@field config markup.config
---@field node markup.node
---@field cmd markup.cmd
---@field reconciler markup.reconciler
---@field object markup.object
---@field singleton markup.singleton
_G.Markup = setmetatable({ core = M, renderers = {} }, {
	__index = function(t, k)
		t[k] = require("markup." .. k)
		return rawget(t, k)
	end,
})

M.Component = Markup.factory.element.component
M.Class = Markup.factory.element.class
M.Fragment = Markup.factory.element.fragment
M.variable = require("markup.reconciler.hook.state")
M.context = Markup.factory.element.context
M.use = require("markup.reconciler.hook.use")
M.effect = require("markup.reconciler.hook.effect")
M.view = require("markup.reconciler.hook.view")

M.hook = {
	variable = require("markup.reconciler.hook.state"),
	context = Markup.factory.element.context,
	use = require("markup.reconciler.hook.use"),
	effect = require("markup.reconciler.hook.effect"),
	view = require("markup.reconciler.hook.view"),
}

setmetatable(M, {
	__call = function(_, ...)
		return Markup.factory.element(...)
	end,
	__index = function(t, k)
		t[k] = function(...)
			return Markup.factory.element(k:lower(), ...)
		end
		return rawget(t, k)
	end,
})

---@private
---@param opts? table
function M.setup(opts)
	Markup.config.merge(opts)
	Markup.cmd.setup()
end

return M
