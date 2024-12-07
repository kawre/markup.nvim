local FiberTag = require("markup.core.fiber.enum").Tag
local markup = require("markup.core")
local u = require("markup.utils")
local log = require("markup.logger") ---@diagnostic disable-line: unused-local

---@class markup.Fiber
---@field props any
---@field pending_props any
---@field type markup.Fiber.type
---@field tag markup.Fiber.tag
---@field state_node markup.Node
---@field alternate? markup.Fiber
---@field child markup.Fiber
---@field sibling markup.Fiber
---@field index integer
local Fiber = {}

---@param returnf markup.Fiber
---@param current? markup.Fiber
---@param wip? markup.Fiber
---@return markup.Fiber
function Fiber.reconcile(returnf, current, wip)
	if type(wip) == "string" or type(wip) == "number" then
		return Fiber.reconcile_single_text_node(returnf, current, wip)
	end

	-- return Fiber.reconcile(returnf, current.child, wip.child)

	-- if vim.islist(wip) then
	-- 	return Fiber.reconcile_children_list(returnf, current, wip)
	-- end
end

function Fiber.reconcile_children_list(returnf, current, wip)
	--
end

---@param returnf markup.Fiber
---@param current? markup.Fiber
---@param element markup.Element.Table
---@return markup.Fiber
function Fiber.reconcile_single_element_node(returnf, current, element)
	local existing = current

	while existing do
		if existing.type == element.type then
			local updated = Fiber.use(existing, element.props)
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

	local fiber = markup.create_fiber(FiberTag.TEXT, content)
	fiber["return"] = returnf
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
