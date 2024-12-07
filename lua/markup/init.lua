local log = require("markup.logger") ---@diagnostic disable-line: unused-local
local enum = require("markup.enum")

---@class markup
---@field Parser markup.Parser.constructor
---@field Window markup.Window.constructor
---@field Renderer markup.Renderer.constructor
---@field TabPage markup.TabPage.constructor
-- Create
---@field Element markup.create_element
---@field Component markup.create_component
---@field Fragment markup.create_fragment
-- CreateElement
---@field Inline markup.Inline.constructor
---@field Block markup.Block.constructor
---@field Flex markup.Flex.constructor
local markup = {}

function markup.setup(opts)
	local config = require("markup.config")
	config.user = vim.tbl_deep_extend("force", config, opts or {})
	config.debug = opts.debug or config.debug
end

require("markup-playground").setup()
require("markup.theme").setup()

return setmetatable(markup, {
	__index = function(_, k)
		return enum:lookup(k)
	end,
})
