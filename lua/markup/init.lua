---@class markup: markup.factory.element
---@field hooks markup.hooks
---@field private setup any
---@field [string] markup.factory.element.new
local M = {}

---@class markup.global
---@field core markup.core
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
---@field layout markup.layout
---@field object markup.object
---@field singleton markup.singleton
---@field parser markup.parser
_G.Markup = setmetatable({ renderers = {} }, {
	__index = function(t, k)
		t[k] = require("markup." .. k)
		return rawget(t, k)
	end,
})

M.hooks = require("markup.reconciler.hooks")

local reactive = require("markup.reactive")
M.signal = reactive.signal
M.memo = reactive.memo
M.effect = reactive.effect
M.untrack = reactive.untrack
M.on_cleanup = reactive.on_cleanup
M.provide = reactive.provide
M.inject = reactive.inject

function M.show(...)
	return require("markup.view.mount").show(...)
end

function M.each(...)
	return require("markup.view.mount").each(...)
end

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

_G.Markup.dispatcher = require("markup.reconciler.dispatcher")
_G.Markup.list = require("markup.collection.list")
_G.Markup.stack = require("markup.collection.stack")

---@private
---@param opts? table
function M.setup(opts)
	Markup.config.merge(opts)
	Markup.cmd.setup()
end

return M
