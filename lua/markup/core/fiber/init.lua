local FiberTag = require("markup.core.fiber.enum").Tag
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

---@param element markup.Element.Table
function Fiber:init(element, parent)
	self.alternate = nil

	self.index = 0
	self.props = element.props
	self.type = element.type
	self.tag = Fiber.static:tag(element)
	self["return"] = parent
end

---@param element markup.Element.Table
---@param parent markup.Fiber
---@return markup.Fiber
function Fiber.static:build_tree(element, parent)
	if type(element) == "string" or type(element) == "number" then
		element = markup.create_element("text", { children = tostring(element) })
	end

	local fiber = Fiber(element, parent)
	local children = fiber.props.children

	if fiber.tag == FiberTag.FUNCTION then
		children = fiber.type(fiber.props)
	elseif fiber.tag == FiberTag.ELEMENT then
		fiber.state_node = fiber.type(fiber.props)
		parent = fiber
	end

	if children and type(children) == "table" then
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

			child_fiber["return"].state_node:append_child(child_fiber.state_node)
		end
	end

	return fiber
end

---@param returnf markup.Fiber
---@param current? markup.Fiber
---@param wip? markup.Fiber
function Fiber.reconcile(returnf, current, wip)
	if type(wip) == "string" or type(wip) == "number" then
		return Fiber.reconcile_single_text_node(returnf, current, wip)
	end

	if vim.islist(wip) then
		return Fiber.reconcile_children_list(returnf, current, wip)
	end
end

function Fiber.reconcile_children_list(returnf, current, wip)
	--
end

---@param returnf markup.Fiber
---@param current? markup.Fiber
---@param element markup.Element.Table
function Fiber.reconcile_single_element_node(returnf, current, element)
	local existing = current

	while existing do
		if existing.type == element.type then
			local updated = use_fiber(existing, element.props)
			updated["return"] = returnf
			return updated
		end
		-- if (existingChild.type === element.type) {
		-- const updatedFiber = useFiber(existingChild, element.props);
		-- updatedFiber.return = returnFiber;
		-- return updatedFiber;
		-- }
	end
	--
end

function Fiber.use(current, props)
	--
end

---@param returnf markup.Fiber
---@param current? markup.Fiber
---@param content string|number
function Fiber.reconcile_single_text_node(returnf, current, content)
	if current and current.tag == FiberTag.TEXT then
		current.pending_props = content
		return current
	end

	local fiber = markup.create_fiber(FiberTag.TEXT, content, returnf)
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
