local log = require("markup.logger") ---@diagnostic disable-line: unused-local
local FiberTag = require("markup.core.fiber.enum").Tag
local FiberFlag = require("markup.core.fiber.enum").Flag
local markup = require("markup.core")

---@class markup.Fiber
---@field props any
---@field pending_props any
---@field memoized_props any
---@field type markup.Fiber.type
---@field tag markup.Fiber.tag
---@field state_node markup.Node
---@field key? any
---@field flag? markup.Fiber.flag
---@field alternate? markup.Fiber
---@field child? markup.Fiber
---@field sibling? markup.Fiber
---@field index integer
local Fiber = {}

---@param current_tree? markup.Fiber
---@param element markup.Element.Table
---@return markup.Fiber?
function Fiber.reconcile(current_tree, element)
	local wip_tree = markup.create_fiber_root()
	wip_tree.child = markup.create_fiber_from_element(element)
	wip_tree.alternate = current_tree

	local unit = wip_tree
	while unit do
		unit = Fiber.process(unit)
	end

	return wip_tree
end

---@param wip markup.Fiber
function Fiber.process(wip)
	local next = Fiber.begin_work(wip.alternate, wip)

	wip.memoized_props = wip.pending_props

	if not next then
		Fiber.complete_work(wip)
	else
		return next
	end
end

---@param current? markup.Fiber
---@param wip markup.Fiber
function Fiber.begin_work(current, wip)
	if current then
		local old_props, new_props = current.memoized_props, wip.pending_props

		if not vim.deep_equal(old_props, new_props) or current.type ~= wip.type then
			wip.flag = FiberFlag.UPDATE
		else
			wip.flag = nil
		end
	else
		wip.flag = nil
	end

	local switch = {
		[FiberTag.FUNCTION] = Fiber.update_function_component,
		[FiberTag.FRAGMENT] = Fiber.update_fragment_component,
		[FiberTag.ELEMENT] = Fiber.update_element_component,
		[FiberTag.ROOT] = Fiber.update_element_component,
		[FiberTag.TEXT] = Fiber.update_text_component,
	}

	assert(switch[wip.tag], ("Invalid Fiber tag: %s"):format(wip.tag))
	local next = switch[wip.tag](current, wip)

	wip.memoized_props = wip.pending_props

	return next
end

function Fiber.complete_work(fiber)
	return fiber
end

---@param current? markup.Fiber
---@param wip markup.Fiber
function Fiber.update_function_component(current, wip)
	local next_children = Fiber.render_with_hooks(wip.type, wip.pending_props)

	if current and wip.flag == FiberFlag.UPDATE then
		-- bailoutHooks(current, workInProgress, renderLanes);
		-- return bailoutOnAlreadyFinishedWork(current, workInProgress, renderLanes);
	end

	wip.child = Fiber.reconcile_children(current, wip, next_children)
	return wip.child
end

function Fiber.update_fragment_component(current, wip)
	return wip.child
end

function Fiber.update_text_component(current, wip)
	return wip.child
end

function Fiber.update_element_component(current, wip)
	return wip.child
end

function Fiber.render_with_hooks(Component, ...)
	return Component(...)
end

function Fiber.delete_child(returnf, child)
	--
end

function Fiber.reconcile_children_list(returnf, current_first_child, new_children)
	--
end

function Fiber.reconcile_children(current, wip, next_children)
	if not current then
		return Fiber.reconcile_child_fibers(wip, nil, next_children)
	else
		return Fiber.reconcile_child_fibers(wip, current.child, next_children)
	end
end

---@param returnf markup.Fiber
---@param current_first_child? markup.Fiber
---@param new_child markup.Fiber
function Fiber.reconcile_child_fibers(returnf, current_first_child, new_child)
	if new_child.tag == FiberTag.FRAGMENT and new_child.props then
		new_child = new_child.props.children
	end

	if (type(new_child) == "string" and new_child ~= "") or type(new_child) == "number" then
		return Fiber.reconcile_single_text(returnf, current_first_child, tostring(new_child))
	end

	if vim.islist(new_child) then
		return Fiber.reconcile_children_list(returnf, current_first_child, new_child)
	end

	return Fiber.delete_remaining_children(returnf, current_first_child)
end

function Fiber.map_existing_children(fiber)
	if not fiber then
		return {}
	end

	local child_map = {}

	local child = fiber.child
	while child do
		local key = child.key or child.index
		child_map[key] = child
		child = child.sibling
	end

	return child_map
end

---@param new_fiber? markup.Fiber
---@param last_placed_index integer
---@param new_index integer
function Fiber.place_child(new_fiber, last_placed_index, new_index)
	if not new_fiber then
		return last_placed_index
	end

	if new_fiber.alternate then
		local old_index = new_fiber.alternate.index

		if old_index >= last_placed_index then
			last_placed_index = old_index
		end
	end

	new_fiber.index = new_index

	return last_placed_index
end

---@param returnf markup.Fiber
---@param current? markup.Fiber
---@param element markup.Element.Table
---@return markup.Fiber?
function Fiber.reconcile_single_element(returnf, current, element)
	local existing = current

	while existing do
		if existing.key == element.key then
			if existing.type == element.type then
				local updated = Fiber.use(existing, element.props)
				updated["return"] = returnf
				return updated
			end

			Fiber.delete_remaining_children(returnf, existing)
			break
		end

		existing = existing.sibling
	end

	local new_fiber = markup.create_fiber_from_element(element)
	new_fiber["return"] = returnf

	if new_fiber.tag == FiberTag.FUNCTION then
		local rendered = new_fiber.type(new_fiber.props)
		return Fiber.reconcile(returnf, nil, rendered)
	elseif new_fiber.tag == FiberTag.FRAGMENT then
		-- return Fiber.reconcile(new_fiber, current, new_fiber)
	elseif new_fiber.tag == FiberTag.ELEMENT then
		new_fiber.state_node = new_fiber.type(new_fiber.props)
		-- return Fiber.reconcile(new_fiber, current, new_fiber.state_node)
	end

	return new_fiber
end

function Fiber.use(fiber, props)
	local clone = markup.create_fiber(fiber.type, props, fiber.key)
	clone.state_node = fiber.state_node
	clone.alternate = fiber
	fiber.alternate = clone
	return clone
end

---@param returnf markup.Fiber
---@param current? markup.Fiber
---@param content string
function Fiber.reconcile_single_text(returnf, current, content)
	if current and current.tag == FiberTag.TEXT then
		current.pending_props = content
		return current
	end

	local fiber = markup.create_fiber(markup.Text, content)
	fiber["return"] = returnf
	return fiber
end

---@param returnf markup.Fiber
---@param current_first_child? markup.Fiber
function Fiber.delete_remaining_children(returnf, current_first_child)
	local child = current_first_child

	while child do
		Fiber.delete_child(returnf, child)
		child = child.sibling
	end
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
