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

---@class markup.Box.constructor.props
---@field children markup.Element[]
---@field spacing? integer
---@field align? markup.Box.align
---@field direction? markup.Box.direction

---@alias markup.Box.constructor fun(props: markup.Element | markup.Box.constructor.props): markup.Box

---@type markup.Box.constructor
local MarkupBox = Box

return MarkupBox
