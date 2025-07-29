---@class markup
---@field inline markup.factory.element
---@field block markup.factory.element
---@field flex markup.factory.element
---@field grid markup.factory.element
---@field component markup.factory.element.component
---@field fragment markup.factory.element.fragment
---@field hooks markup.hooks
---@field private setup any
---@field [string] markup.factory.element
---@overload fun(type: any, props?: markup.factory.element.props, style?: markup.factory.element.style): markup.element
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

M.hooks = require("markup.hooks")

setmetatable(M, { ---@diagnostic disable-line: param-type-mismatch
	__call = function(_, ...)
		return Markup.factory.element(...)
	end,
	__index = function(t, k)
		k = k:lower()

		t[k] = function(...)
			if Markup.factory.element[k] then
				return Markup.factory.element[k](...)
			else
				return Markup.factory.element(k, ...)
			end
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
