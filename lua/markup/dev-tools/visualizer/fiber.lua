local FiberTag = require("markup.core.reconciler.enum").Tag
local FiberFlag = require("markup.core.reconciler.enum").Flag

---@param root markup.Fiber
---@param opts? table
return function(root, opts)
	opts = vim.tbl_deep_extend("keep", opts or {}, {
		exclude_ids = false,
		hl = true,
	})

	local lines = {}

	---@param fiber markup.Fiber
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
			table.insert(entries, { (" (key = %s)"):format(fiber.key), "Statement" })
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

	return lines
end
