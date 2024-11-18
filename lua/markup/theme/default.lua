local M = {}

---Get highlight group value by name.
---
---@param name string String for looking up highlight group.
---@return table
local function hl(name)
	local highlight = vim.api.nvim_get_hl(0, { name = name, link = false })
	setmetatable(highlight, {
		__index = function(self, key)
			if key == "bg" then
				return self.background
			end
			if key == "fg" then
				return self.foreground
			end

			return nil
		end,
	})

	return highlight
end

---@alias markup.highlights table<string, vim.api.keyset.highlight>

---@return markup.highlights
M.get = function()
	return {
		normal = hl("Normal"),

		tree_title = { fg = hl("Normal").fg },
		tree_indent = { fg = hl("NonText").fg },
		tree_icon_expand = { fg = hl("Number").fg },
		tree_icon_collapse = { fg = hl("Number").fg },
	}
end

return M
