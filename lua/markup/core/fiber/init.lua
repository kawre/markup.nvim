local FiberTag = require("markup.core.fiber.types").Tag
local markup = require("markup.core")
local u = require("markup.utils")
local log = require("markup.logger") ---@diagnostic disable-line: unused-local

---@class markup.Fiber : markup.Object
---@field type any
---@field state_node markup.Node
---@field hooks any
---@field alternate? markup.Fiber
---@field child markup.Fiber
---@field sibling markup.Fiber
---@field index integer
---@field memoized_state any
---@field pending_props any
---@field memoized_props any
---@field update_queue any
local Fiber = markup.Object("markup.fiber")

function Fiber.static:tag(element)
	if type(element.type) == "function" then
		return FiberTag.FUNCTION
	elseif u.is_class(element.type, markup.Element) then
		return FiberTag.ELEMENT
	elseif u.is_class(element.type, markup.Text) then
		return FiberTag.TEXT
	else
		error("Unknown element type: " .. element.type)
	end
end

---@param element markup.ElementObject
function Fiber:init(element, parent)
	self.alternate = nil

	self.index = 0
	self.props = element.props
	self.type = element.type
	self.tag = Fiber.static:tag(element)
	self["return"] = parent
end

---@param element markup.ElementObject
---@param parent markup.Fiber
---@return markup.Fiber
function Fiber.static:build_tree(element, parent)
	if type(element) == "string" or type(element) == "number" then
		local e = markup.create_element("text", { children = tostring(element) })
		return Fiber(e, parent)
	end

	local fiber = Fiber(element, parent)

	if fiber.tag == FiberTag.ELEMENT then
		parent = fiber
	end

	local children = fiber.props.children
	if fiber.tag == FiberTag.FUNCTION then
		children = fiber.type(fiber.props)
	end

	if fiber.tag == FiberTag.ELEMENT then
		fiber.state_node = fiber.type(fiber.props)
	end

	if children then
		if type(children) ~= "table" then
			return fiber
		end

		local prev_sibling = nil

		children = vim.islist(children) and children or { children }

		for i, child in ipairs(children) do
			local child_fiber = Fiber.static:build_tree(child, parent)

			if i == 1 then
				fiber.child = child_fiber
			else
				prev_sibling.sibling = child_fiber ---@diagnostic disable-line: inject-field
			end

			prev_sibling = child_fiber

			-- local node = child_fiber.state_node
			-- if node then
			-- 	fiber.state_node:append_child(node)
			-- 	child_fiber["return"] = fiber
			-- end
			-- child_fiber["return"].state_node:append_child(child_fiber.state_node)
			-- log.info(child_fiber)
		end
	end

	return fiber
end

function Fiber:print()
	local function print_fiber_tree(fiber, depth)
		if not fiber then
			return
		end

		local indent = ("    "):rep(depth or 0)

		print(indent .. ("Fiber: %s (%s)"):format(fiber.type, fiber.tag))

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
