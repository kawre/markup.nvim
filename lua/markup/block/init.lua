local NuiLine = require("nui.line")
local NuiText = require("nui.text")
local Opts = require("leetcode-ui.opts")
local utils = require("leetcode-ui.utils")
local log = require("leetcode.logger")
local Object = require("markup.object")

---@class markup.Block.props : markup.Element.props
---@field children markup.Block
---@field color string
---@field max_width_chars? integer

---@class markup.Block : markup.Element
---@field _ markup.Block.props
local Block = Object("MarkupBlock")

function Block:init(props)
	self._ = vim.tbl_deep_extend("force", {
		children = {},
		color = "Normal",
		max_width_chars = nil,
	}, props)
end

---@class markup.Block.constructor.props
---@field xd integer

---@alias markup.Block.constructor fun(props: markup.Block.constructor.props): markup.Block

---@type markup.Block.constructor
local MarkupBlock = Block

return MarkupBlock
