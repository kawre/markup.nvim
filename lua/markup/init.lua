---@class markup: markup.factory.element
---@field private setup any
---@field [string] markup.factory.element.new
local M = {}

---@class markup.global
---@field core markup.core
---@field animate markup.animate
---@field log markup.logger
---@field util markup.util
---@field devkit markup.devkit
---@field playground markup.playground
---@field factory markup.factory
---@field window markup.window
---@field config markup.config
---@field cmd markup.cmd
---@field layout markup.layout
---@field object markup.object
---@field singleton markup.singleton
_G.Markup = setmetatable({ views = setmetatable({}, { __mode = "k" }) }, {
	__index = function(t, k)
		t[k] = require("markup." .. k)
		return rawget(t, k)
	end,
})

local reactive = require("markup.reactive")
M.signal = reactive.signal
M.memo = reactive.memo
M.effect = reactive.effect
M.untrack = reactive.untrack
M.on_cleanup = reactive.on_cleanup
M.provide = reactive.provide
M.inject = reactive.inject

--- The view a component is rendered in.
---@return markup.view
function M.use_view()
	local view = reactive.inject(Markup.view.CONTEXT)
	assert(view, "`use_view` must be called inside a component")
	return view
end

--- Binds a key for as long as the calling component stays mounted.
---@param lhs string
---@param fn function
---@param opts? vim.keymap.set.Opts|{ mode?: string }
function M.use_key(lhs, fn, opts)
	opts = vim.deepcopy(opts or {})
	local mode = opts.mode or "n"
	opts.mode = nil

	local view = M.use_view()
	local win = view.win

	-- Components can overlap, such as pages during a slide, so the latest one wins
	-- and the key goes back to the one before it when that unmounts.
	local id = mode .. " " .. lhs
	local stack = view.key_stacks[id]
	if not stack then
		stack = {}
		view.key_stacks[id] = stack
		win:map(mode, lhs, function()
			stack[#stack].fn()
		end, opts)
	end

	local entry = { fn = fn }
	table.insert(stack, entry)

	reactive.on_cleanup(function()
		for i, other in ipairs(stack) do
			if other == entry then
				table.remove(stack, i)
				break
			end
		end

		if #stack == 0 then
			view.key_stacks[id] = nil
			win:unmap(mode, lhs)
		end
	end)
end

--- A number that animates towards the values written to it.
---@see markup.animate.value
function M.animated(...)
	return Markup.animate.value(...)
end

--- Cycles through values, such as a spinner.
---@see markup.animate.frames
function M.frames(...)
	return Markup.animate.frames(...)
end

--- A bar with eighths of a cell of precision.
---@see markup.view.components.progress
function M.progress(...)
	return require("markup.view.components").progress(...)
end

--- An image, drawn over its box in the layout.
---@see markup.view.mount.image
function M.image(...)
	return require("markup.view.mount").image(...)
end

--- A spinner, a random one unless named.
---@see markup.view.components.spinner
function M.spinner(...)
	return require("markup.view.components").spinner(...)
end

function M.slide(...)
	return require("markup.view.mount").slide(...)
end

function M.collapse(...)
	return require("markup.view.mount").collapse(...)
end

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

_G.Markup.list = require("markup.collection.list")

---@private
---@param opts? table
function M.setup(opts)
	Markup.config.merge(opts)
	Markup.cmd.setup()
end

return M
