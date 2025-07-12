local FiberTag = require("markup.core.reconciler.enum").Tag
local FiberFlag = require("markup.core.reconciler.enum").Flag
local picker = require("snacks.picker")
local log = require("markup.logger")

---@param root? markup.Node
return function(root)
	local lines = {}

	---@param node markup.Node
	local function print_node_tree(node, depth, prefix)
		if not node then
			return
		end

		depth = depth or 0
		prefix = prefix or ""

		-- local mark = (fiber.child or fiber.sibling) and "├╴" or "└╴"
		local mark = "├╴"
		local indent_marker = prefix .. (depth > 0 and mark or "")

		local xd
		if node.type == "element" then
			xd = { " " .. node.tag_name, "DiagnosticHint" }
		else
			xd = { " " .. node.props }
		end

		local entries = {
			{ indent_marker, "SignColumn" },
			xd,
			{ " " },
			{ ("(%s)"):format(node.type), "Conceal" },
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

		for _, child in ipairs(node.child_nodes) do
			print_node_tree(child, depth + 1, prefix .. (depth > 0 and "│ " or ""))
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
		title = "Node Tree",
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
