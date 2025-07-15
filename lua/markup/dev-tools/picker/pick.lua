---@param conf snacks.picker.Config
return function(conf)
	local picker = require("snacks.picker")

	conf = vim.tbl_deep_extend("keep", conf, {
		layout = {
			preset = "default",
		},
		win = {
			preview = { minimal = true },
		},
		title = "dev tools",
		preview = "preview",
		format = function(item)
			local ret = {}
			vim.tbl_map(function(col)
				if type(col) == "table" then
					ret[#ret + 1] = col
				else
					ret[#ret + 1] = { col }
				end
			end, item.item.entry)
			return ret
		end,
	})

	picker.pick(conf)
end
