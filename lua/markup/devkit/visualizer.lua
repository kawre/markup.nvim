local FiberTag = require("markup.reconciler.enum").Tag

---@class markup.devkit.visualizer
local M = {}

local function remove_hl(tbl)
	return vim.tbl_map(function(t)
		return table.concat(vim.tbl_map(function(chunk)
			if type(chunk) == "table" then
				return chunk[1]
			else
				return chunk
			end
		end, t))
	end, tbl)
end

---@param root markup.fiber
---@param opts? table
function M.fiber(root, opts)
	opts = vim.tbl_deep_extend("keep", opts or {}, {
		exclude_ids = false,
		hl = true,
	})

	local lines = {}

	---@param fiber markup.fiber
	local function print_fiber_tree(fiber, depth, prefix)
		if not fiber then
			return
		end

		depth = depth or 0
		prefix = prefix or ""

		local mark = (fiber.child or fiber.sibling) and "├╴" or "└╴"
		local indent = prefix .. (depth > 0 and mark or "")

		local entries = {
			{ indent, "SignColumn" },
		}

		if fiber.tag == FiberTag.FRAGMENT then
			table.insert(entries, { " " .. fiber.type, "Number" })
		elseif fiber.tag == FiberTag.ROOT then
			table.insert(entries, { " fiber root", "Error" })
		elseif fiber.tag == FiberTag.TEXT then
			table.insert(entries, { " " .. fiber.state_node.text_content })
		elseif fiber.tag == FiberTag.FUNCTION then
			table.insert(entries, { "󰊕 Component", "Label" })
		else
			table.insert(entries, { " " .. tostring(fiber.type), "DiagnosticHint" })
			if fiber.memoized_props and fiber.memoized_props.children then
				local children = fiber.memoized_props.children
				if type(children) == "string" or type(children) == "number" then
					table.insert(entries, { "  " .. tostring(fiber.pending_props.children) })
				end
			end
		end

		if fiber.key then
			table.insert(entries, { (" [key = %s]"):format(fiber.key), "Statement" })
		end
		table.insert(entries, { (" (%s)"):format(fiber.tag), "Conceal" })

		if not opts.exclude_ids then
			table.insert(entries, { " " })
			table.insert(entries, { ("  %s "):format(fiber.__id), "LspInlayHint" })
		end

		table.insert(lines, entries)

		if fiber.child then
			print_fiber_tree(fiber.child, depth + 1, prefix .. (depth > 0 and "│ " or ""))
		end

		if fiber.sibling then
			print_fiber_tree(fiber.sibling, depth, prefix)
		end
	end

	print_fiber_tree(root, 0, "")

	return opts.hl and lines or remove_hl(lines)
end

---@param root? markup.node
---@param opts? table
function M.node(root, opts)
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

		local label = node.type == "element" and { " " .. node.tag_name, "DiagnosticHint" }
			or { " " .. node.text_content }

		local entries = {
			{ indent, "SignColumn" },
			label,
			{ " " },
			{ ("(%s)"):format(node.type), "Conceal" },
		}

		if not opts.exclude_ids then
			table.insert(entries, { ("  %s "):format(node.__id), "LspInlayHint" })
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

	return opts.hl and lines or remove_hl(lines)
end

---@param root? markup.Render.Box
---@param opts? table
function M.render(root, opts)
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
			{ indent, "SignColumn" },
			{ node:name() },
			{ node.dirty and "  " or " ", "Number" },
			{ ("(%s)"):format(node.node.tag_name), "Conceal" },
		}

		if not opts.exclude_ids then
			table.insert(entries, { ("  %s "):format(node.__id), "LspInlayHint" })
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

	return opts.hl and lines or remove_hl(lines)
end

return M
