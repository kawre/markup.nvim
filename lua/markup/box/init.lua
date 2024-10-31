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

-- ---@param renderer markup.Renderer
-- function Box:draw(renderer)
-- 	local content = self:content()
--
-- 	for _, element in ipairs(content) do
-- 		element:render(renderer, self)
-- 	end
-- end

function Box:after_draw(renderer)
	local state = renderer:get_state(self)
	local parent_state = renderer:get_state(state.parent)
	local start, endd, box, lengths = state.start, state.endd, state.box, state.lengths

	for row = start.row, endd.row do
		if self._.align == "center" then
			local length = lengths[row]
			local padding = math.floor((parent_state.box.width - length) / 2)
			log.debug({
				row = row,
				width = parent_state.box.width,
				length = length,
				padding = padding,
			})
			renderer:pad(padding, row, start.col)
		elseif self._.align == "end" then
			-- local length = lengths[row]
			-- local padding = math.floor((window_width - length) / 2)
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
