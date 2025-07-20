local FiberTag = require("markup.core.reconciler.enum").Tag
local FiberFlag = require("markup.core.reconciler.enum").Flag
local log = require("markup.logger")

---@param root? markup.Render.Box
---@param opts? table
return function(root, opts)
	opts = vim.tbl_deep_extend("keep", opts or {}, {
		exclude_ids = false,
		hl = true,
	})

	local lines = {}

	local function print_node_tree(node, depth, prefix, is_last)
		if not node then
			return
		end

		depth = depth or 0
		prefix = prefix or ""

		local mark = not (vim.tbl_isempty(node.children) and is_last) and "├╴" or "└╴"
		local indent = prefix .. (depth > 0 and mark or "")

		local entries = {
			{ indent, opts.hl and "SignColumn" or nil },
			{ node:name() },
			{ node.dirty and "  " or " ", opts.hl and "Number" or nil },
			{ ("(%s)"):format(node.node.tag_name), opts.hl and "Conceal" or nil },
		}

		if not opts.exclude_ids then
			table.insert(
				entries,
				{ ("  %s "):format(node.__id), opts.hl and "LspInlayHint" or nil }
			)
		end

		table.insert(lines, entries)

		for i, child in ipairs(node.children or {}) do
			print_node_tree(
				child,
				depth + 1,
				prefix .. (depth > 0 and "│ " or ""),
				i == #node.children
			)
		end
	end

	print_node_tree(root)

	return lines
end
