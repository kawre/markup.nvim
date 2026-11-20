-- `:checkhealth markup`

local M = {}

function M.check()
	local config = require("markup.config")

	vim.health.start("Neovim")
	local min = config.min_nvim
	local current = vim.version()
	if vim.version.ge(current, min) then
		vim.health.ok(("Neovim %s (%s or newer is supported)"):format(tostring(current), min))
	else
		vim.health.error(
			("Neovim %s is older than %s, the oldest markup.nvim supports"):format(
				tostring(current),
				min
			),
			{ "Update Neovim" }
		)
	end

	vim.health.start("Native engine")
	local ok, err = pcall(require, "markup.core")
	if ok then
		vim.health.ok("markup_core loaded")
	else
		vim.health.error("markup_core failed to load: " .. tostring(err), {
			"Build it with `cargo build --release` in the plugin's directory",
		})
	end
end

return M
