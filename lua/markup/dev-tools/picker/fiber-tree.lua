local FiberTag = require("markup.core.reconciler.enum").Tag
local FiberFlag = require("markup.core.reconciler.enum").Flag
local picker = require("snacks.picker")

---@param root markup.Fiber
return function(root)
	local lines = {}

	---@param fiber markup.Fiber
	local function print_fiber_tree(fiber, depth, prefix)
		if not fiber then
			return
		end

		depth = depth or 0
		prefix = prefix or ""

		local type_str = fiber.tag == FiberTag.ROOT and "ROOT"
			or fiber.tag == FiberTag.TEXT and "'" .. fiber.pending_props .. "'"
			or fiber.type

		local mark = (fiber.child or fiber.sibling) and "├╴" or "└╴"
		local indent_marker = prefix .. (depth > 0 and mark or "")
		local icon = fiber.tag == FiberTag.FRAGMENT and " "
			or fiber.tag == FiberTag.FUNCTION and "󰊕 "
			or fiber.tag == FiberTag.TEXT and " "
			or " "

		local entries = {
			{ indent_marker, "SignColumn" },
			{ icon, fiber.state_node and "DiagnosticHint" or "Error" },
			{ tostring(type_str) },
			{ " " },
			{ ("(%s)"):format(fiber.tag), "Conceal" },
		}
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

	picker.pick({
		items = lines,
		layout = {
			preset = "default",
		},
		win = {
			preview = { minimal = true },
		},
		title = "Fiber Tree",
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
end
