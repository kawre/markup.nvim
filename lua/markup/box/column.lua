local markup = require("markup")
local utils = require("markup.utils")
local log = require("markup.logger")

---@class markup.Box.Column : markup.Box
local ColumnBox = markup.Box:extend("MarkupColumnBox")

---@param renderer markup.Renderer
function ColumnBox:draw(renderer)
	local content = self:content()
	for i, element in ipairs(content) do
		element:render(renderer, self)
		if self._.spacing > 0 and i ~= #content then
			renderer:endl(self._.spacing)
		end
	end
end

---@param renderer markup.Renderer
function ColumnBox:after_draw(renderer)
	local state = renderer:get_state(self)
	log.info("col")

	for row = state.start.row, state.endd.row do
		local padding, length = 0, state.lengths[row]

		if self._.align == "start" then
			padding = state.box.width - length
			renderer:pad(padding, row, state.start.col + length)
		elseif self._.align == "center" then
			padding = math.floor((state.box.width - length) / 2)
			renderer:pad_after(padding, row)
			renderer:pad(padding, row, state.start.col + padding + length)
		elseif self._.align == "end" then
			padding = state.box.width - length
			renderer:pad_after(padding, row)
		end
	end

	ColumnBox.super.after_draw(self, renderer)
end

---@type markup.Box.constructor
local MarkupColumnBox = ColumnBox

return MarkupColumnBox
