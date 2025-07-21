local FiberTag = require("markup.core.reconciler.enum").Tag
local FiberFlag = require("markup.core.reconciler.enum").Flag

---@param root? markup.Render.Box
---@param exclude_ids? boolean
return function(root, exclude_ids)
	local lines = {}
	local lines2 = {}

	---@param node markup.Render.Box
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
			{ node.dirty and "  " or " ", "Number" },
			{ ("(%s)"):format(node.node.tag_name), "Conceal" },
			-- { ("(%s)"):format(node.type), "Conceal" },
		}
		local text_mapped = vim.tbl_map(function(e)
			return e[1]
		end, entries)

		if not exclude_ids then
			table.insert(entries, { " " })
			table.insert(entries, { ("  %s "):format(node.__id), "LspInlayHint" })
		end

		table.insert(
			lines2,
			table.concat(vim.tbl_map(function(v)
				return v[1]
			end, entries))
		)

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

	return lines, lines2
end
