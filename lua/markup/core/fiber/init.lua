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

	local fiber = Fiber(element)
	fiber["return"] = parent

	if type(element) == "string" then
		local e = markup.create_element("text", { text = element })
		return Fiber.static:build_tree(e, fiber)
	end

	if type(element.type) == "function" then
		return Fiber.static:build_tree(element.type(element.props), fiber)
	end

	local children = element.props.children
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

	return fiber
end

return Fiber
