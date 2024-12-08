local log = require("markup.logger") ---@diagnostic disable-line: unused-local
local FiberTag = require("markup.core.reconciler.enum").Tag
local FiberFlag = require("markup.core.reconciler.enum").Flag
local markup = require("markup.core")

---@class markup.Reconciler
local Reconciler = {}

Reconciler.currently_rendering_fiber = nil
Reconciler.update_queue = markup.Array()

---@param renderer_root markup.Renderer.Root
---@return markup.Fiber
function Reconciler.reconcile(renderer_root)
	return Reconciler.work_loop(renderer_root.current)
end

---@param root markup.Fiber
function Reconciler.work_loop(root)
	local stack = markup.Array({ root })

	while #stack >= 1 do
		local unit = stack:remove()

		local next = Reconciler.process(unit)
		log.info(next)

		if next then
			stack:insert(next)
		else
			Reconciler.complete_work(unit)
		end
	end

	return root
end

---@param wip markup.Fiber
function Reconciler.process(wip)
	local next = Reconciler.begin_work(wip.alternate, wip)
	wip.memoized_props = wip.pending_props
	return next
end

---@param current? markup.Fiber
---@param wip markup.Fiber
function Reconciler.begin_work(current, wip)
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

	local next = markup.Switch(wip.tag, {
		[FiberTag.FUNCTION] = Reconciler.update_function_component,
		[FiberTag.FRAGMENT] = Reconciler.update_fragment_component,
		[FiberTag.ELEMENT] = Reconciler.update_element_component,
		[FiberTag.ROOT] = Reconciler.update_root_component,
		[FiberTag.TEXT] = Reconciler.update_text_component,

		default = function()
			error(("Invalid Fiber tag: %s"):format(wip.tag))
		end,
	})
	log.info(wip.tag)

	return next(current, wip)
end

function Reconciler.complete_work(fiber)
	return fiber
end

---@param current? markup.Fiber
---@param wip markup.Fiber
function Reconciler.update_function_component(current, wip)
	local next_children = Reconciler.render_with_hooks(current, wip)

	if current and wip.flag == FiberFlag.UPDATE then
		-- bailoutHooks(current, workInProgress, renderLanes);
		-- return bailoutOnAlreadyFinishedWork(current, workInProgress, renderLanes);
	end

	wip.child = Reconciler.reconcile_children(current, wip, next_children)
	return wip.child
end

function Reconciler.update_fragment_component(current, wip)
	return nil
end

function Reconciler.update_root_component(current, wip)
	assert(current, "Root must have a current fiber, this is a bug.")

	wip.child = Reconciler.reconcile_children(current, wip, wip.pending_props.children)
	return wip.child
end

function Reconciler.update_text_component(current, wip)
	return nil
end

---@param current? markup.Fiber
---@param wip markup.Fiber
function Reconciler.update_element_component(current, wip)
	-- local prev_props = current and current.memoized_props
	local next_props = wip.pending_props
	local next_children = next_props.children

	wip.child = Reconciler.reconcile_children(current, wip, next_children)
	return wip.child
end

---@param current? markup.Fiber
---@param wip markup.Fiber
function Reconciler.render_with_hooks(current, wip)
	local Component = wip.type
	local props = wip.pending_props

	-- wip.memoized_state = nil
	-- if current and current.memoized_state then
	-- 	wip.memoized_state = current.memoized_state
	-- end

	local children = Component(props)

	return children
end

function Reconciler.delete_child(returnf, child)
	--
end

---@param returnf markup.Fiber
---@param child markup.xElement
function Reconciler.create_child(returnf, child)
	if (type(child) == "string" and child ~= "") or type(child) == "number" then
		local fiber = markup.create_fiber_from_text(tostring(child))
		fiber["return"] = returnf
		return fiber
	end

	if child then
		local fiber = markup.create_fiber_from_element(child)
		fiber["return"] = returnf
		return fiber
	end

	return nil
end

---@param existing table<any, markup.Fiber>
---@param returnf markup.Fiber
---@param new_index integer
---@param new_child markup.xElement
function Reconciler.update_from_map(existing, returnf, new_index, new_child)
	if (type(new_child) == "string" and new_child ~= "") or type(new_child) == "number" then
		local matched = existing[new_index]
		return Reconciler.update_text_node(returnf, matched, tostring(new_child))
	end

	if new_child.type then
		local matched = existing[new_child.key or new_index]
		return Reconciler.update_element_node(returnf, matched, new_child)
	end

	return nil
end

---@param returnf markup.Fiber
---@param current? markup.Fiber
---@param content string
function Reconciler.update_text_node(returnf, current, content)
	if current and current.tag == FiberTag.TEXT then
		-- If the existing fiber is a text node, update it
		local existing = Reconciler.use(current, content)
		existing["return"] = returnf
		return existing
	else
		-- Create a new text node
		local fiber = markup.create_fiber_from_text(content)
		fiber["return"] = returnf
		return fiber
	end
end

---@param returnf markup.Fiber
---@param current? markup.Fiber
---@param element markup.xElement
function Reconciler.update_element_node(returnf, current, element)
	if current and current.type ~= element.type then
		-- If the existing fiber is not an element node, create a new one
		local existing = Reconciler.use(current, element.props)
		existing["return"] = returnf
		return existing
	else
		-- Create a new element node
		local fiber = markup.create_fiber_from_element(element)
		fiber["return"] = returnf
		return fiber
	end
end

---@param returnf markup.Fiber
---@param current_first_child? markup.Fiber
---@param new_children markup.xElement[]
function Reconciler.reconcile_children_list(returnf, current_first_child, new_children)
	local new_index = 1
	local last_placed_index = 1

	local old_fiber = current_first_child
	local next_old_fiber = nil
	local prev_new_fiber = nil
	local result_first_child = nil

	while old_fiber and new_index <= #new_children do
		last_placed_index = Reconciler.place_child(old_fiber, last_placed_index, new_index)
		old_fiber = old_fiber.sibling
		new_index = new_index + 1
	end

	if new_index == #new_children then
		Reconciler.delete_remaining_children(returnf, old_fiber)
		return result_first_child
	end

	if not old_fiber then
		while new_index <= #new_children do
			local new_fiber = Reconciler.create_child(returnf, new_children[new_index])

			if new_fiber then
				return nil
			end

			if prev_new_fiber then
				prev_new_fiber.sibling = new_fiber
			else
				result_first_child = new_fiber
			end

			prev_new_fiber = new_fiber
			new_index = new_index + 1
		end

		return result_first_child
	end

	local existing_children = Reconciler.map_remaining_children(returnf, old_fiber)

	while new_index <= #new_children do
		local new_fiber = Reconciler.update_from_map(
			existing_children,
			returnf,
			new_index,
			new_children[new_index]
		)

		if new_fiber then
			last_placed_index = Reconciler.place_child(new_fiber, last_placed_index, new_index)

			if prev_new_fiber then
				prev_new_fiber.sibling = new_fiber
			else
				result_first_child = new_fiber
			end

			prev_new_fiber = new_fiber
		end

		new_index = new_index + 1
	end

	return result_first_child
end

---@param current? markup.Fiber
---@param wip markup.Fiber
---@param next_children markup.xElement
function Reconciler.reconcile_children(current, wip, next_children)
	return Reconciler.reconcile_child_fibers(wip, (current or {}).child, next_children)
end

---@param returnf markup.Fiber
---@param current_first_child? markup.Fiber
---@param new_child markup.xElement
function Reconciler.reconcile_child_fibers(returnf, current_first_child, new_child)
	if (type(new_child) == "string" and new_child ~= "") or type(new_child) == "number" then
		return Reconciler.reconcile_single_text(returnf, current_first_child, tostring(new_child))
	end

	if vim.islist(new_child) then
		return Reconciler.reconcile_children_list(returnf, current_first_child, new_child)
	elseif type(new_child) == "table" then
		return Reconciler.reconcile_single_element(returnf, current_first_child, new_child)
	end

	-- return Fiber.delete_remaining_children(returnf, current_first_child)
end

---@param returnf markup.Fiber
---@param current_first_child? markup.Fiber
---@return table<any, markup.Fiber>
function Reconciler.map_remaining_children(returnf, current_first_child)
	local existing = {}

	local child = current_first_child
	while child do
		existing[child.key or child.index] = child
		child = child.sibling
	end

	return existing
end

---@param new_fiber? markup.Fiber
---@param last_placed_index integer
---@param new_index integer
function Reconciler.place_child(new_fiber, last_placed_index, new_index)
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
---@param current_first_child? markup.Fiber
---@param element markup.xElement
---@return markup.Fiber?
function Reconciler.reconcile_single_element(returnf, current_first_child, element)
	local key = element.key
	local child = current_first_child

	local created
	if element.type == FiberTag.FRAGMENT then
		created = markup.create_fiber_from_fragment(element.props.children)
	else
		created = markup.create_fiber_from_element(element)
	end

	created["return"] = returnf
	return created
end

function Reconciler.use(fiber, props)
	local clone = markup.create_fiber(fiber.type, props, fiber.key)
	clone.state_node = fiber.state_node
	clone.alternate = fiber
	fiber.alternate = clone
	return clone
end

---@param returnf markup.Fiber
---@param current? markup.Fiber
---@param content string
function Reconciler.reconcile_single_text(returnf, current, content)
	if current and current.tag == FiberTag.TEXT then
		current.pending_props = content
		return current
	end

	local fiber = markup.create_fiber_from_text(content)
	fiber["return"] = returnf
	return fiber
end

---@param returnf markup.Fiber
---@param current_first_child? markup.Fiber
function Reconciler.delete_remaining_children(returnf, current_first_child)
	local child = current_first_child

	while child do
		Reconciler.delete_child(returnf, child)
		child = child.sibling
	end
end

function Reconciler:print()
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

return Reconciler
