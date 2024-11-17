local markup = require("markup")
local log = require("markup.logger") ---@diagnostic disable-line: unused-local

---@class markup.Extmark.props : markup.Text.props
---@field extmark vim.api.keyset.set_extmark

---@class markup.Extmark : markup.Text
---@field protected super markup.Text
---@field protected _ markup.Extmark.props
local Extmark = markup.Text:extend("markup.node.text.extmark") ---@diagnostic disable-line: undefined-field

---@param extmark vim.api.keyset.set_extmark
---@param parent markup.Node
function Extmark:init(extmark, parent)
	local content = table.concat(
		vim.tbl_map(function(tbl)
			log.debug(tbl)
			return tbl[1]
		end, extmark.virt_text),
		""
	)

	Extmark.super.init(self, "", parent)
	self._.extmark = extmark
end

-- function Extmark:content()
-- 	return ""
-- end

-- function Extmark:render() end

function Extmark:highlight(linenr, byte_start)
	self.owner:buf_set_extmark(nil, linenr, byte_start, {
		virt_text = self._.extmark.virt_text,
		virt_text_pos = "inline",
	})
	-- vim.api.nvim_buf_set_extmark(buffer, ns_id, line, col, opts)
end

return Extmark
