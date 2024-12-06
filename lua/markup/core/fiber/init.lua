local markup = require("markup.core")
local log = require("markup.logger") ---@diagnostic disable-line: unused-local

---@class markup.Fiber : markup.Object
---@field type any
---@field state_node markup.Node
---@field hooks any
---@field alternate? markup.Fiber
-- linked list
---@field child markup.Fiber
---@field sibling markup.Fiber
---@field index integer
-- state
---@field memoized_state any
---@field pending_props any
---@field memoized_props any
---@field update_queue any
local Fiber = markup.Object("markup.fiber")

---@param element markup.Element2
function Fiber:init(element)
	self.state = {}
	self.props = {}
	self.hook_index = 0
	self.hooks = {}
	self.alternate = nil

	self.props = element.props
	self.type = element.type
end

---@return markup.Fiber?
function Fiber.static:build_tree(element, parent)
	if not element then
		return nil
	end

	if type(element) == "string" or type(element) == "number" then
		return markup.create_element("text", { children = tostring(element) })
	end

	local fiber = Fiber(element)
	fiber["return"] = parent

	local children = element.props.children
	if type(element.type) == "function" then
		children = element.type(element.props)
	end

	if children then
		local prev_sibling = nil

		children = vim.islist(children) and children or { children }

		for i, child in ipairs(children) do
			local child_fiber = Fiber.static:build_tree(child, fiber)

			if i == 1 then
				fiber.child = child_fiber
			else
				prev_sibling.sibling = child_fiber ---@diagnostic disable-line: inject-field
			end

			prev_sibling = child_fiber
		end
	end

	fiber.state_node = element

	return fiber
end

function Fiber:print()
	local function print_fiber_tree(fiber, depth)
		if not fiber then
			return
		end

		local indent = string.rep("\t", depth or 0)

		local fiber_type = fiber.type or "unknown"
		print(indent .. string.format("Fiber: %s", fiber_type))

		if fiber.child then
			print_fiber_tree(fiber.child, (depth or 0) + 1)
		end

		if fiber.sibling then
			print_fiber_tree(fiber.sibling, depth)
		end
	end

	print_fiber_tree(self, 0)
end

return Fiber
