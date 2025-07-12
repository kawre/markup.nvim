local FiberTag = require("markup.core.reconciler.enum").Tag
local FiberFlag = require("markup.core.reconciler.enum").Flag
local picker = require("snacks.picker")
local log = require("markup.logger")

---@param root? markup.Render.Node
return function(root)
	local lines = {}

	---@param node markup.Render.Node
	local function print_node_tree(node, depth, prefix, is_last)
		if not node then
			return
		end

		depth = depth or 0
		prefix = prefix or ""

		local mark = not (vim.tbl_isempty(node.children) and is_last) and "├╴" or "└╴"
		local indent_marker = prefix .. (depth > 0 and mark or "")

		-- local xd
		-- if node.__name == "element" then
		-- 	xd = { " " .. node.tag_name, "DiagnosticHint" }
		-- else
		-- 	xd = { " " .. node.props }
		-- end

		local entries = {
			{ indent_marker, "SignColumn" },
			{ node:name() },
			{ " " },
			-- { ("(%s)"):format(node.type), "Conceal" },
		}
		local text_mapped = vim.tbl_map(function(e)
			return e[1]
		end, entries)

		table.insert(lines, {
			text = table.concat(text_mapped, " "),
			item = {
				entry = entries,
				value = node,
			},
			preview = {
				text = vim.inspect(node, { depth = 2 }),
				ft = "lua",
			},
		})

		for i, child in ipairs(node.children) do
			print_node_tree(
				child,
				depth + 1,
				prefix .. (depth > 0 and "│ " or ""),
				i == #node.children
			)
		end
	end

	print_node_tree(root, 0, "")

	picker.pick({
		items = lines,
		layout = {
			preset = "default",
		},
		win = {
			preview = { minimal = true },
		},
		title = "Render Tree",
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

	return lines
end
