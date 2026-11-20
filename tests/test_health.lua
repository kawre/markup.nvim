---@module 'mini.test'

local new_set = MiniTest.new_set
local eq = MiniTest.expect.equality
local child = MiniTest.new_child_neovim()

local T = new_set({
	hooks = {
		pre_case = function()
			child.restart({ "-u", "scripts/minimal_init.lua" })
			child.lua([[
				require("markup")
				reports = {}
				local function report(kind)
					return function(msg) reports[#reports + 1] = kind .. " " .. msg end
				end
				vim.health = { start = report("start"), ok = report("ok"), warn = report("warn"), error = report("error") }
			]])
		end,
		post_once = function()
			child.stop()
		end,
	},
})

T["says the engine has the version of the plugin"] = function()
	child.lua([[require("markup.health").check()]])
	local version = child.lua_get("require('markup.config').version")
	eq(
		vim.tbl_contains(
			child.lua_get("reports"),
			("ok Engine version %s, the same as the plugin"):format(version)
		),
		true
	)
end

T["warns of an engine from another version"] = function()
	child.lua([[
		require("markup.core").version = "0.0.0"
		require("markup.health").check()
	]])
	local warned = vim.tbl_filter(function(line)
		return line:find("^warn Engine version 0.0.0") ~= nil
	end, child.lua_get("reports"))
	eq(#warned, 1)
end

T["the plugin, Cargo.toml and the Claude Code plugin have the same version"] = function()
	local version = child.lua_get("require('markup.config').version")
	local cargo =
		table.concat(vim.fn.readfile("Cargo.toml"), "\n"):match("\nversion = \"([^\"]+)\"")
	eq(cargo, version)
	local function json(path)
		return vim.json.decode(table.concat(vim.fn.readfile(path), "\n"))
	end
	eq(json(".claude-plugin/plugin.json").version, version)
	eq(json(".claude-plugin/marketplace.json").plugins[1].version, version)
end

return T
