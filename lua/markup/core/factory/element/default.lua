local M = {}

M.grid = {
	display = "grid",
}
M.flex = {
	display = "flex",
}
M.hflex = {
	display = "flex",
	horizontal = true,
}
M.block = {
	display = "block",
}
M.inline = {
	display = "inline",
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
