--- `position = "fixed"`: content pinned to the top of a view's window.
---
--- A buffer scrolls as a whole, so pinned content cannot live in it. It gets a
--- view of its own in a float over the window, and a spacer in the buffer keeps
--- the float from covering the first rows.
---
--- With `overlay` there is no spacer, so appearing moves nothing. Fixed elements
--- stack in order, and an empty one takes no room.

local protocol = require("markup.view.protocol")
local reactive = require("markup.reactive")

local api = vim.api

---@class markup.view.fixed
---@field parent markup.view
---@field view markup.view
---@field win markup.window
---@overload fun(parent: markup.view, spacer: integer, content: any, style?: string): markup.view.fixed
local M = Markup.object()

---@param parent markup.view
---@param style? string|false
function M.winhighlight(parent, style)
	if style then
		return ("Normal:%s"):format(style)
	end
	return parent.win:win_valid() and vim.wo[parent.win.win].winhighlight or ""
end

---@param parent markup.view
---@param spacer? integer node that reserves the rows in the parent
---@param content any
---@param style? string|false highlight for the whole band, false for none
function M:new(parent, spacer, content, style)
	self.parent = parent
	self.spacer = spacer
	self.height = 0

	self.win = Markup.window({
		position = "float",
		relative = "win",
		win = parent.win.win or api.nvim_get_current_win(),
		row = 0,
		col = 0,
		width = 0,
		height = 1,
		border = "none",
		backdrop = false,
		enter = false,
		focusable = false,
		minimal = true,
		show = false,
		zindex = 45,
		wo = { winhighlight = M.winhighlight(parent, style) },
	})

	self.view = Markup.view(self.win)
	self.view.devtool = true
	self.view:on_commit(function()
		self:sync()
	end)

	self.group = api.nvim_create_augroup(("markup_fixed_[%s]"):format(self.win.id), { clear = true })

	api.nvim_create_autocmd("WinResized", {
		group = self.group,
		callback = function()
			if parent.win:win_valid() and vim.tbl_contains(vim.v.event.windows, parent.win.win) then
				self:reposition()
			end
		end,
	})

	api.nvim_create_autocmd("WinClosed", {
		group = self.group,
		callback = function(event)
			-- The window forgets its id before this runs, so compare with ours.
			if tonumber(event.match) == self.parent_win then
				self:hide()
			end
		end,
	})

	parent.win:on_show(function()
		self:show()
	end)

	self.view:render(content)
	self:show()
end

function M:show()
	if self.disposed or not self.parent.win:win_valid() then
		return
	end
	self.parent_win = self.parent.win.win
	self.win.opts.win = self.parent_win
	self.win:show()
	reactive.flush()
	self:reposition()
end

function M:hide()
	if self.win:win_valid() then
		self.win:close()
	end
end

--- Follows the width of the window underneath.
function M:reposition()
	if self.win:win_valid() then
		self:place()
		self.view.commands:resize(api.nvim_win_get_width(self.win.win))
		self.view:request_commit()
	end
end

--- Stacks the float below the fixed elements before it.
function M:place()
	local row = 0
	for _, other in ipairs(self.parent.fixed) do
		if other == self then
			break
		end
		row = row + other.height
	end

	self.win.opts.row = row
	if self.win:win_valid() then
		self.win:update()
		api.nvim_win_set_config(self.win.win, { hide = self.height == 0 })
	end
end

--- Keeps the float and the reserved rows as tall as the content.
function M:sync()
	local height = self.view.engine:describe(protocol.ROOT).outer_height or 0
	if height == self.height then
		return
	end
	self.height = height

	self.win.opts.height = math.max(height, 1)
	for _, fixed in ipairs(self.parent.fixed) do
		fixed:place()
	end

	if self.spacer then
		self.parent.commands:set_style(self.spacer, "height", height)
		self.parent:request_commit()
	end
end

function M:dispose()
	self.disposed = true
	api.nvim_del_augroup_by_id(self.group)
	self.view:destroy()
	self:hide()
end

return M
