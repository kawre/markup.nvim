local log = require("markup.logger") ---@diagnostic disable-line: unused-local

---@class markup.Theme
local theme = {}

local id, cache = 1, {}

---@param style? markup.Element.style
function theme.create_dynamic_hl(style)
	if not style or vim.tbl_isempty(style) then
		return
	end

	local hl_name

	if type(style) == "table" then
		---@cast style table

		table.sort(style)
		local readable = vim.inspect(style)

		if not cache[readable] then
			local name = "MarkupDynamicStyle_" .. id
			vim.api.nvim_set_hl(0, name, style)
			cache[readable] = name
			id = id + 1
		end

		hl_name = cache[readable]
	else
		hl_name = style
	end

	return hl_name
end

function theme.load()
	for style_str, name in pairs(cache) do
		local style = load("return " .. style_str)()
		vim.api.nvim_set_hl(0, style, name)
	end
end

function theme.setup()
	vim.api.nvim_create_autocmd("ColorScheme", {
		group = vim.api.nvim_create_augroup("markup.colorscheme_sync", {}),
		desc = "Colorscheme Synchronizer",
		callback = theme.load,
	})

	theme.load()
end

return theme
