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
		Normal = hl("Normal"),
		NormalSB = hl("NormalSB"),
		NormalNC = hl("NormalNC"),
		NormalFloat = hl("NormalFloat"),
		FloatBorder = hl("FloatBorder"),
		FloatTitle = hl("FloatTitle"),
		WinBar = hl("WinBar"),
		WinBarNC = hl("WinBarNC"),

		Code = { fg = hl("Type").fg, bg = hl("Normal").bg },

		TreeTitle = { fg = hl("Normal").fg },
		TreeIndent = { fg = hl("NonText").fg },
		TreeIconExpand = { fg = hl("Number").fg },
		TreeIconCollapse = { fg = hl("Number").fg },
	}
end

return M
