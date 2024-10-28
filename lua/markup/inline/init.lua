local NuiLine = require("nui.line")
local NuiText = require("nui.text")
local Opts = require("leetcode-ui.opts")
local utils = require("leetcode-ui.utils")
local log = require("leetcode.logger")
local Object = require("markup.object")

---@class markup.Inline.props
---@field children markup.Inline
---@field color string
---@field max_width_chars? integer

---@class markup.Inline : markup.Element
---@field props markup.Inline.props
local Inline = Object("MarkupInline")

function Inline:init(props)
	self._ = vim.tbl_deep_extend("force", {
		children = {},
		color = "Normal",
		max_width_chars = nil,
	}, props)
end

---@type fun(props: string | markup.Inline.props): markup.Inline
local MarkupInline = Inline

return MarkupInline
