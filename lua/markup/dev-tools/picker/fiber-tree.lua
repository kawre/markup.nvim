local FiberTag = require("markup.core.reconciler.enum").Tag
local FiberFlag = require("markup.core.reconciler.enum").Flag

---@param root markup.Fiber
---@param exclude_ids? boolean
return function(root, exclude_ids)
	local lines = {}
	local lines2 = {}

	---@param fiber markup.Fiber
	local function print_fiber_tree(fiber, depth, prefix)
		if not fiber then
			return
		end

		depth = depth or 0
		prefix = prefix or ""

		-- local type_str = fiber.tag == FiberTag.ROOT and "ROOT"
		-- 	or fiber.tag == FiberTag.TEXT and "'" .. fiber.state_node.text_content .. "'"
		-- 	or fiber.type

		local mark = (fiber.child or fiber.sibling) and "├╴" or "└╴"
		local indent_marker = prefix .. (depth > 0 and mark or "")
		-- local icon = fiber.tag == FiberTag.FRAGMENT and " "
		-- 	or fiber.tag == FiberTag.FUNCTION and "󰊕 "
		-- 	or fiber.tag == FiberTag.TEXT and " "
		-- 	or " "
		local xd
		if fiber.tag == FiberTag.FRAGMENT then
			xd = { { " " .. fiber.type, "Number" } }
		elseif fiber.tag == FiberTag.ROOT then
			xd = { { " fiber root", "Error" } }
		elseif fiber.tag == FiberTag.TEXT then
			xd = { { " " .. fiber.state_node.text_content } }
		elseif fiber.tag == FiberTag.FUNCTION then
			xd = { { "󰊕 " .. tostring("Component"), "Label" } }
		else
			xd = { { " " .. tostring(fiber.type), "DiagnosticHint" } }

			local children = fiber.memoized_props.children
			if
				1
				and ((type(children) == "string" and children ~= "") or type(children) == "number")
			then
				table.insert(xd, 1, { "  " .. tostring(fiber.pending_props.children) })
			end
		end

		local entries = {
			{ indent_marker, "SignColumn" },
			{ " " },
			{ fiber.key and ("(key = %s) "):format(fiber.key) or "", "Statement" },
			{ ("(%s)"):format(fiber.tag), "Conceal" },
		}
		for _, value in ipairs(xd) do
			table.insert(entries, 2, value)
		end
		if not exclude_ids then
			table.insert(entries, { " " })
			table.insert(entries, { ("  %s "):format(fiber.__id), "LspInlayHint" })
		end
		table.insert(
			lines2,
			table.concat(vim.tbl_map(function(v)
				return v[1]
			end, entries))
		)
		local text_mapped = vim.tbl_map(function(e)
			return e[1]
		end, entries)

		table.insert(lines, {
			text = table.concat(text_mapped, " "),
			item = {
				entry = entries,
				value = fiber,
			},
			preview = {
				text = vim.inspect(fiber, { depth = 2 }),
				ft = "lua",
			},
		})

		if fiber.child then
			print_fiber_tree(fiber.child, depth + 1, prefix .. (depth > 0 and "│ " or ""))
		end

		if fiber.sibling then
			print_fiber_tree(fiber.sibling, depth, prefix)
		end
	end

	print_fiber_tree(root, 0, "")

	return lines, lines2
end
