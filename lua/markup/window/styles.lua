local M = {}

M.default = {
	show = true,
	fixbuf = true,
	relative = "editor",
	position = "float",
	minimal = true,
	wo = {
		winhighlight = "Normal:MarkupNormal,NormalNC:MarkupNormalNC,WinBar:MarkupWinBar,WinBarNC:MarkupWinBarNC",
	},
	bo = {},
	keys = {
		q = "close",
	},
}

M.float = {
	position = "float",
	backdrop = 60,
	height = 0.9,
	width = 0.9,
	zindex = 50,
}

M.minimal = {
	wo = {
		cursorcolumn = false,
		cursorline = false,
		cursorlineopt = "both",
		colorcolumn = "",
		fillchars = "eob: ,lastline:…",
		list = false,
		listchars = "extends:…,tab:  ",
		number = false,
		relativenumber = false,
		signcolumn = "no",
		spell = false,
		winbar = "",
		statuscolumn = "",
		wrap = false,
		sidescrolloff = 0,
	},
}

M.split = {
	position = "bottom",
	height = 0.4,
	width = 0.4,
}

return M
