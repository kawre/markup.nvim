local M = {}

function M.merge(props)
	return vim.tbl_extend("keep", props, M.default, props or {})
end

---@type markup.box.props
M.default = {
	display = "block",
	margin_top = 0,
	margin_right = 0,
	margin_bottom = 0,
	margin_left = 0,
	padding_top = 0,
	padding_right = 0,
	padding_bottom = 0,
	padding_left = 0,
	width = "auto",
	height = "auto",
	max_height = "auto",
	max_width = "auto",
	min_height = "auto",
	min_width = "auto",
	spacing = 0,
	justify = "start",
	align = "stretch",
	basis = "auto",
	vertical = false,
	reverse = false,
	sizing = "inner",
	style = {},
}

M.grid = {
	display = "grid",
}

M.flex = {
	display = "flex",
}

M.hflex = {
	display = "flex",
	vertical = false,
}

M.vflex = {
	display = "flex",
	vertical = true,
}

M.block = {
	display = "block",
}

M.inline = {
	display = "inline",
	sizing = "outer",
}

M.anchor = {
	style = { underline = true, fg = "#89b4fb" },
}

M.code = {
	style = { link = "MarkupCode" },
}

M.italic = {
	style = { italic = true },
}

M.mark = {
	style = { background = "yellow", color = "black" },
}

M.strike = {
	style = { strikethrough = true },
}

M.strong = {
	style = { bold = true },
}

M.sub = {
	style = { color = "#9399b3" },
}

M.sup = {
	style = { color = "#9399b3" },
}

M.underline = {
	style = { underline = true },
}

return M
