local log = require("markup.logger") ---@diagnostic disable-line: unused-local

---@param root? markup.Node
---@param opts? table
return function(root, opts)
	opts = vim.tbl_deep_extend("keep", opts or {}, {
		exclude_ids = false,
		hl = true,
	})

	local lines = {}

	local function traverse(node, depth, prefix, is_last)
		if not node then
			return
		end

		depth = depth or 0
		prefix = prefix or ""

		local has_children = not vim.tbl_isempty(node.child_nodes)
		local mark = (has_children or not is_last) and "├╴" or "└╴"
		local indent = prefix .. (depth > 0 and mark or "")

		local label = node.type == "element"
				and { " " .. node.tag_name, opts.hl and "DiagnosticHint" or nil }
			or { " " .. node.text_content }

		local entries = {
			{ indent, opts.hl and "SignColumn" or nil },
			label,
			{ " " },
			{ ("(%s)"):format(node.type), opts.hl and "Conceal" or nil },
		}

		if not opts.exclude_ids then
			table.insert(
				entries,
				{ ("  %s "):format(node.__id), opts.hl and "LspInlayHint" or nil }
			)
		end

		table.insert(lines, entries)

		for i, child in ipairs(node.child_nodes) do
			traverse(
				child,
				depth + 1,
				prefix .. (depth > 0 and "│ " or ""),
				i == #node.child_nodes
			)
		end
	end

	traverse(root)

	return lines
end
