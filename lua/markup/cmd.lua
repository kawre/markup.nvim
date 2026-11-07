---@class markup.cmd
local cmd = {}

---@param tbl table
local function cmds_keys(tbl)
	return vim.tbl_filter(function(key)
		if type(key) ~= "string" then
			return false
		end
		if key:sub(1, 1) == "_" then
			return false
		end
		if tbl[key]._private then
			return false
		end

		return true
	end, vim.tbl_keys(tbl))
end

---@return string[], string[]
function cmd.parse(args)
	local parts = vim.split(vim.trim(args), "%s+")
	if args:sub(-1) == " " then
		parts[#parts + 1] = ""
	end

	local options = {}
	for _, part in ipairs(parts) do
		local opt = part:match("(.-)=.-")
		if opt then
			table.insert(options, opt)
		end
	end

	return parts, options
end

---@param _ string
---@param line string
---
---@return string[]
function cmd.complete(_, line)
	local args, options = cmd.parse(line:gsub("Markup%s", ""))
	return cmd.rec_complete(args, options, cmd.commands)
end

---@param args string[]
---@param options string[]
---@param cmds table<string,any>
---
---@return string[]
function cmd.rec_complete(args, options, cmds)
	if not cmds or vim.tbl_isempty(args) then
		return {}
	end

	if not cmds._args and cmds[args[1]] then
		return cmd.rec_complete(args, options, cmds[table.remove(args, 1)])
	end

	local txt, keys = args[#args], cmds_keys(cmds)
	if cmds._args then
		local option_keys = cmds_keys(cmds._args)
		option_keys = vim.tbl_filter(function(key)
			return not vim.tbl_contains(options, key)
		end, option_keys)
		option_keys = vim.tbl_map(function(key)
			return ("%s="):format(key)
		end, option_keys)
		keys = vim.tbl_extend("force", keys, option_keys)

		local s = vim.split(txt, "=")
		if s[2] and cmds._args[s[1]] then
			local vals = vim.split(s[2], ",")
			return vim.tbl_filter(function(key)
				return not vim.tbl_contains(vals, key) and key:find(vals[#vals], 1, true) == 1
			end, cmds._args[s[1]])
		end
	end

	return vim.tbl_filter(function(key)
		return not vim.tbl_contains(args, key) and key:find(txt, 1, true) == 1
	end, keys)
end

function cmd.exec(args)
	local cmds = cmd.commands

	local options = vim.empty_dict()
	for s in vim.gsplit(args.args:lower(), "%s+", { trimempty = true }) do
		local opt = vim.split(s, "=")

		if opt[2] then
			options[opt[1]] = vim.split(opt[2], ",", { trimempty = true })
		elseif cmds then
			cmds = cmds[s]
		else
			break
		end
	end

	if cmds and type(cmds[1]) == "function" then
		cmds[1](options) ---@diagnostic disable-line
	else
		Markup.log.error(("Invalid command: `%s %s`"):format(args.name, args.args))
	end
end

function cmd.setup()
	vim.api.nvim_create_user_command("Markup", cmd.exec, {
		bar = true,
		bang = true,
		nargs = "?",
		desc = "Markup",
		complete = cmd.complete,
	})
end

cmd.commands = {
	inspect = {
		function()
			Markup.devkit.inspect()
		end,
	},
	playground = {
		function()
			Markup.playground.open()
		end,
		run = {
			function()
				Markup.playground.run()
			end,
		},
		layout = {
			function()
				Markup.playground.open({ file = "layout.lua" })
			end,
		},
	},
}

return cmd
