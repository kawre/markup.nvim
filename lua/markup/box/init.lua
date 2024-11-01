local markup = require("markup")
local utils = require("markup.utils")
local log = require("markup.logger")

---@alias markup.Box.align "start"|"center"|"end"
---@alias markup.Box.direction "row"|"column"

---@class markup.Box.props : markup.Element.props
---@field align markup.Box.align
---@field spacing integer
---@field direction markup.Box.direction

---@class markup.Box : markup.Element
---@field _ markup.Box.props
local Box = markup.Block:extend("MarkupBox")

---@param props markup.Box.constructor.props
function Box:init(props)
	props = vim.tbl_deep_extend("force", {
		align = "start",
		direction = "column",
		spacing = 0,
		children = {},
	}, props)

	Box.super.init(self, props)
end

---@param renderer markup.Renderer
function Box:draw(renderer)
	local content = self:content()
	for i, element in ipairs(content) do
		element:render(renderer, self)

		if self._.spacing > 0 and i ~= #content then
			if self._.direction == "column" then
				renderer:endl(self._.spacing)
			elseif self._.direction == "row" then
				renderer:pad(self._.spacing)
			end
		end
	end
end

---@param renderer markup.Renderer
function Box:after_draw(renderer)
	local state = renderer:get_state(self)

	for row = state.start.row, state.endd.row do
		local padding, length = 0, state.lengths[row]

		if self._.align == "start" then
			padding = state.box.width - length
			renderer:pad(padding, row, state.start.col + length)
		elseif self._.align == "center" then
			padding = math.floor((state.box.width - length) / 2)
			renderer:pad(padding, row)
			renderer:pad(padding, row, padding + state.start.col + length)
		elseif self._.align == "end" then
			padding = state.box.width - length
			renderer:pad_after(padding, row)
		end
	end

	Box.super.after_draw(self, renderer)
end

---@class markup.Box.constructor.props
---@field children markup.Element[]
---@field spacing? integer
---@field align? markup.Box.align
---@field direction? markup.Box.direction

---@alias markup.Box.constructor fun(props: markup.Element | markup.Box.constructor.props): markup.Box

---@type markup.Box.constructor
local MarkupBox = Box

return MarkupBox
