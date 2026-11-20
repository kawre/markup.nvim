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
		-- An engine left from another version, such as one downloaded for a
		-- release while the plugin moved on, may not speak the same protocol.
		local engine = err.version
		if engine == config.version then
			vim.health.ok(("Engine version %s, the same as the plugin"):format(engine))
		else
			vim.health.warn(
				("Engine version %s, the plugin is %s"):format(tostring(engine), config.version),
				{ "Build it again with `cargo build --release`, or update the plugin to a release" }
			)
		end
	else
		vim.health.error("markup_core failed to load: " .. tostring(err), {
			"Build it with `cargo build --release` in the plugin's directory",
		})
	end
end

return M
