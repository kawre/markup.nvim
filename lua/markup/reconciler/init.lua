local Tag = require("markup.reconciler.enum").Tag
local Flag = require("markup.reconciler.enum").Flag

---@class markup.reconciler: markup.object
---@field render_scheduled boolean
---@field current_fiber? markup.fiber
---@field current_hook? markup.fiber.hook
---@field wip_hook? markup.fiber.hook
---@field work_stack table
---@field work_stack_visited table
---@field last_context_dep? markup.hooks.context.dep
---@overload fun(fiber: markup.fiber): markup.fiber
local M = Markup.singleton()

---@param rootf markup.fiber
function M.call(rootf)
	M.current_fiber = nil
	M.current_hook = nil
	M.wip_hook = nil
	M.last_context_dep = nil

	local new_rootf = M.work_loop(rootf)
	M.commit(new_rootf)
	return new_rootf
end

---@param rootf markup.fiber
function M.fresh_stack(rootf)
	local wip = M.create_wip(rootf, rootf.pending_props)

	M.work_stack = Markup.collection.stack()
	M.work_stack:push(wip)
	M.work_stack_visited = {}

	return M.work_stack
end

---dfs reconciliation
---@param rootf markup.fiber
function M.work_loop(rootf)
	M.work_stack = M.fresh_stack(rootf)

	local unit
	while M.work_stack.len > 0 do
		unit = M.work_stack:pop()
		M.process_unit(unit)
	end

	return unit
end

---@param unit markup.fiber
---@return markup.fiber?
function M.process_unit(unit)
	if M.work_stack_visited[unit] then
		return M.complete_unit(unit)
	end

	M.current_fiber = unit
	local next = M.begin_work(unit.alternate, unit)
	M.current_fiber = nil

	unit.memoized_props = unit.pending_props
	-- unit.memoized_state = M.current_hook

	M.work_stack:push(unit)
	M.work_stack:push(next)
	M.work_stack_visited[unit] = true
end

---@param current? markup.fiber
---@param wip markup.fiber
---@return markup.fiber
function M.begin_work(current, wip)
	-- first check if the fiber can be reused
	if current then
		local old_props, new_props = current.memoized_props, wip.pending_props
		if
			current.type == wip.type
			and old_props == new_props
			and wip:check_flags(Flag.NONE)
			and not M.has_pending_updates(wip)
		then
			-- nothing to do, we can reuse the current fiber
			return M.bailout(wip)
		end
	end

	local next_work ---@type function
	if --
		wip.tag == Tag.ELEMENT
	then
		next_work = M.update_element_component
	elseif --
		wip.tag == Tag.FUNCTION
	then
		next_work = M.update_function_component
	elseif --
		wip.tag == Tag.TEXT
	then
		next_work = M.update_text_component
	elseif --
		wip.tag == Tag.FRAGMENT
	then
		next_work = M.update_fragment_component
	elseif --
		wip.tag == Tag.ROOT
	then
		next_work = M.update_root_component
	elseif --
		wip.tag == Tag.CONTEXT
	then
		next_work = M.update_context_component
	else
		error(("Invalid Fiber tag: %s"):format(wip.tag))
	end

	---@diagnostic disable-next-line: return-type-mismatch
	return next_work(current, wip)
end

---@param unit markup.fiber
function M.complete_unit(unit)
	local current, wip = unit.alternate, unit

	if --
		wip.tag == Tag.ELEMENT
	then
		if current and wip.state_node then
			M.update_single_node(wip)
		else
			M.place_single_node(wip)
			M.populate_state_node(wip)
		end
	elseif --
		wip.tag == Tag.TEXT
	then
		if current and wip.state_node then
			M.update_node_text(wip)
		else
			M.place_single_node(wip)
		end
	elseif --
		wip.tag == Tag.FUNCTION
	then
		wip:clear_flags(Flag.PLACEMENT)
		wip:clear_flags(Flag.UPDATE)
	elseif --
		wip.tag == Tag.ROOT
	then
		if wip:check_flags(Flag.PLACEMENT) then
			M.populate_state_node(wip)
			wip:clear_flags(Flag.PLACEMENT)
		end
	end

	M.work_stack:push(unit.sibling)
end

---@param fiber markup.fiber
---@return markup.fiber
function M.find_parent(fiber)
	-- TODO: keep track of the parent during commit phase, it would make it faster
	local parent = fiber and fiber["return"]
	while parent and not parent.state_node do
		parent = parent["return"]
	end
	Markup.assert.bug(parent and parent.state_node, "Element ancestor must exist")
	return parent
end

---@param wip markup.fiber
function M.place_single_node(wip)
	wip.state_node = Markup.factory.node.from_fiber(wip)

	if type(wip.pending_props) == "table" and M.is_valid_text(wip.pending_props.children) then
		-- handle single text child elements
		M.place_single_text_child(wip)
	end
	wip:set_flags(Flag.PLACEMENT)
end

---@param wip markup.fiber
function M.update_single_node(wip)
	local current = wip.alternate
	assert(current, "`current` must exist for updating a single node")

	if current.memoized_props ~= wip.pending_props then
		wip:set_flags(Flag.UPDATE)
	end

	-- if M.is_valid_text(wip.pending_props.children) then
	-- 	-- handle single text child elements
	-- 	if M.is_valid_text(current.memoized_props.children) then
	-- 		M.update_single_text_child(wip)
	-- 	else
	-- 		M.place_single_text_child(wip)
	-- 	end
	-- else
	-- 	wip.state_node:replace_props(wip.pending_props)
	-- end
	--
	-- wip:clear_flags(Flag.UPDATE)
end

---@param fiber markup.fiber
function M.place_single_text_child(fiber)
	assert(fiber.state_node, "`fiber.state_node` must exist for text child placement")

	local text_node = Markup.factory.node.from_text(fiber.pending_props.children)
	fiber.state_node:append_child(text_node)
end

---@param fiber markup.fiber
function M.bailout(fiber)
	M.clone_child_fibers(fiber)
	return fiber.child
end

---@param current? markup.fiber
---@param wip markup.fiber
function M.update_function_component(current, wip)
	local next_children = M.render_with_hooks(current, wip)

	wip.child = M.reconcile_children(current, wip, next_children)
	return wip.child
end

function M.update_fragment_component(current, wip)
	wip.child = M.reconcile_children(current, wip, wip.pending_props.children)
	return wip.child
end

---@param current markup.fiber
---@param wip markup.fiber
function M.update_root_component(current, wip)
	Markup.assert.bug(current, "Root must always have an alternate fiber")

	wip.child = M.reconcile_children(current, wip, wip.pending_props.children)
	return wip.child
end

---@param current markup.fiber
---@param wip markup.fiber
function M.update_context_component(current, wip)
	local ctx = wip.type
	local next_value = wip.pending_props.value
	ctx.current = next_value

	wip.child = M.reconcile_children(current, wip, wip.pending_props.children)
	return wip.child
end

---@param current? markup.fiber
---@param wip markup.fiber
function M.update_text_component(current, wip)
	if not current then
		wip:set_flags(Flag.PLACEMENT)
	elseif current.memoized_props ~= wip.pending_props then
		wip:set_flags(Flag.UPDATE)
	end
end

---@param fiber markup.fiber
function M.create_instance(fiber)
	Markup.assert.bug(not fiber.state_node, "`fiber.state_node` must not exist during creation")

	fiber:set_flags(Flag.PLACEMENT)

	-- if fiber.tag == FiberTag.FUNCTION then
	-- 	fiber.state_node = fiber.type(fiber.pending_props)
	-- elseif fiber.tag == FiberTag.ELEMENT then
	-- 	-- fiber.state_node =
	-- elseif fiber.tag == FiberTag.ROOT then
	-- end
	-- fiber.state_node.frame = M.renderer

	return fiber
end

function M.is_direct_text_child(fiber)
	local parent = fiber["return"]
	return parent and parent.tag == Tag.ELEMENT
end

---@param current? markup.fiber
---@param wip markup.fiber
function M.update_element_component(current, wip)
	local next_props = wip.pending_props
	local next_children = next_props and next_props.children

	if not current then
		wip:set_flags(Flag.PLACEMENT)
	elseif wip.state_node and current.memoized_props ~= wip.pending_props then
		wip:set_flags(Flag.UPDATE)
	end

	if M.is_valid_text(next_children) then
		-- dont return, keep the function going to delete the remaining children
		next_children = nil
	end

	wip.child = M.reconcile_children(current, wip, next_children)
	return wip.child
end

---@param fiber markup.fiber
function M.has_pending_updates(fiber)
	if fiber.tag ~= "function" then
		return false
	end

	local hook = fiber.memoized_state
	while hook do
		if (hook.queue and hook.queue.pending) or hook.need_update then
			return true
		end
		hook = hook.next
	end
	return false
end

---@param current? markup.fiber
---@param wip markup.fiber
function M.render_with_hooks(current, wip)
	-- clear the hooks to make space for the next hooks
	M.current_hook = nil
	M.wip_hook = nil

	-- if there are pending updates, update the state
	Markup.dispatcher.resolve_hook_updates(wip)

	-- wip.memoized_state = nil
	-- wip.update_queue = nil

	local Component = wip.type
	local props = wip.pending_props
	local children = Component(props) -- re-render the component

	Markup.assert.user(
		not (M.current_hook and M.current_hook.next),
		"Rendered fewer hooks than expected. This may be caused by an accidental early return statement."
	)
	-- wip.memoized_state = M.current_hook
	M.current_hook = nil
	M.wip_hook = nil

	wip:clear_flags(Flag.UPDATE)

	return children
end

---@param returnf markup.fiber
---@param child markup.fiber
function M.delete_child(returnf, child)
	if not returnf.deletions then
		returnf.deletions = { child }
		returnf:set_flags(Flag.CHILD_DELETE)
	else
		table.insert(returnf.deletions, child)
	end
end

---@param returnf markup.fiber
---@param child markup.element
function M.create_child(returnf, child)
	if M.is_valid_text(child) then
		local fiber = Markup.factory.fiber.from_text(child) ---@diagnostic disable-line: param-type-mismatch
		fiber["return"] = returnf
		return fiber
	end

	if child then
		local el = M.prepare_element(child)
		if el then
			local fiber = Markup.factory.fiber.from_element(el)
			fiber["return"] = returnf
			return fiber
		end
	end

	return nil
end

---@param content any
function M.is_valid_text(content)
	return (type(content) == "string" and content ~= "") or type(content) == "number"
end

---@param content any
function M.should_be_fragment(content)
	if
		-- type(content) == "table"
		-- or (type(content) == "table" and Markup.util.typeof(content, "list"))
		vim.islist(content)
	then
		return #content ~= 0
	else
		return false
	end
end

---@param element markup.element
function M.is_host_element(element)
	return element.typeof == "root" or element.typeof == "element"
end

---@param content any
function M.is_valid_element(content)
	if not getmetatable(content) then
		return false
	end ---@cast content markup.element

	-- if type(content.type) == "string" then
	-- 	local children = content.props.children
	-- 	if not children or (type(children) == "table" and vim.tbl_isempty(children)) then
	-- 	-- if not children or (type(children) == "table" and vim.tbl_isempty(children)) then
	-- 		return false
	-- 	end
	-- end

	return true
end

---@param returnf markup.fiber
---@param old_fiber? markup.fiber
---@param new_child markup.element
function M.update_slot(returnf, old_fiber, new_child)
	local key = old_fiber and old_fiber.key

	if M.is_valid_text(new_child) then
		if key then
			return nil
		end

		return M.update_text_node(returnf, old_fiber, new_child)
	end

	if new_child and new_child.key == key then
		local el = M.prepare_element(new_child)
		if el then
			return M.update_element_node(returnf, old_fiber, el)
		end
	end

	return nil
end

---@param fiber markup.fiber
function M.clone_child_fibers(fiber)
	if not fiber.child then
		return nil
	end

	---@type markup.fiber
	local current_child = fiber.child

	local new_child = M.create_wip(current_child, current_child.pending_props)
	fiber.child = new_child
	new_child["return"] = fiber

	while current_child ~= nil and current_child.sibling ~= nil do
		current_child = current_child.sibling

		new_child.sibling = M.create_wip(current_child, current_child.pending_props)
		new_child = new_child.sibling

		new_child["return"] = fiber
	end

	new_child.sibling = nil
end

---@param current markup.fiber
---@param props any
function M.create_wip(current, props)
	local wip = current.alternate

	if not wip then
		wip = Markup.factory.fiber(current.tag, props, current.key)
		wip.tag = current.tag
		wip.element_type = current.element_type
		wip.type = current.type
		wip.state_node = current.state_node
		wip.alternate = current
		current.alternate = wip
	else
		wip.pending_props = props
		wip.type = current.type
	end

	wip.pending_props = props
	wip.memoized_state = current.memoized_state
	wip.memoized_props = current.memoized_props
	wip.flags = current.flags

	wip.child = current.child
	wip.deps = current.deps
	wip.hook = current.hook
	wip.sibling = current.sibling
	wip.index = current.index
	wip.__id = current.__id

	return wip
end

function M.prepare_element(element)
	if not element then
		return nil
	end

	local el = element
	if M.should_be_fragment(el) then
		el = Markup.factory.element.fragment(el)
	end

	return M.is_valid_element(el) and el
end

---@param existing table<any, markup.fiber>
---@param returnf markup.fiber
---@param new_index integer
---@param new_child markup.element
function M.update_from_map(existing, returnf, new_index, new_child)
	if M.is_valid_text(new_child) then
		local matched = existing[new_index]
		return M.update_text_node(returnf, matched, new_child)
	end

	if new_child then
		local el = M.prepare_element(new_child)
		if el then
			local matched = existing[el.key or new_index]
			return M.update_element_node(returnf, matched, el)
		end
	end

	return nil
end

---@param returnf markup.fiber
---@param current? markup.fiber
---@param content any
function M.update_text_node(returnf, current, content)
	if current and current.tag == Tag.TEXT then
		-- If the existing fiber is a text node, update it
		local existing = M.use_fiber(current, content)
		existing["return"] = returnf
		return existing
	else
		-- Create a new text node
		local fiber = Markup.factory.fiber.from_text(content)
		fiber["return"] = returnf
		return fiber
	end
end

---@param fiber markup.fiber
function M.update_node_text(fiber)
	local old_text, new_text = fiber.alternate.pending_props, fiber.pending_props
	local node = fiber.state_node

	if old_text ~= new_text then
		node:set_text_content(new_text)
		-- fiber:clear_flags(Flag.UPDATE)
	end
end

---@param fiber markup.fiber
function M.update_single_text_child(fiber)
	local text_node = fiber.state_node.child_nodes[1]
	assert(text_node:is("text"))

	text_node:set_text_content(fiber.pending_props.children)
end

---@param returnf markup.fiber
---@param current? markup.fiber
---@param element markup.element
function M.update_element_node(returnf, current, element)
	if current and current.type == element.type then
		-- If the existing fiber is not an element node, create a new one
		local existing = M.use_fiber(current, element.props)
		existing["return"] = returnf
		return existing
	else
		-- Create a new element node
		local fiber = Markup.factory.fiber.from_element(element)
		fiber["return"] = returnf
		return fiber
	end
end

---@param returnf markup.fiber
---@param current_first_child? markup.fiber
---@param new_children markup.element[]
function M.reconcile_children_list(returnf, current_first_child, new_children)
	local new_index, last_placed_index = 1, 1

	new_children = vim.tbl_filter(function(i) -- TODO this should be done in the while loop
		return i and i -- filter `false` and `nil` out
	end, new_children)

	local old_fiber = current_first_child
	local next_old_fiber, prev_new_fiber, result_first_child

	while old_fiber and new_index <= #new_children do
		if old_fiber.index > new_index then
			next_old_fiber = old_fiber
			old_fiber = nil
		else
			next_old_fiber = old_fiber.sibling
		end

		local new_fiber = M.update_slot(returnf, old_fiber, new_children[new_index])

		if not new_fiber then
			if not old_fiber then
				old_fiber = next_old_fiber
			end
			break
		end

		if old_fiber and not new_fiber.alternate then
			M.delete_child(returnf, old_fiber)
		end

		last_placed_index = M.place_child(new_fiber, last_placed_index, new_index)

		if not prev_new_fiber then
			result_first_child = new_fiber
		else
			prev_new_fiber.sibling = new_fiber
		end

		prev_new_fiber = new_fiber
		old_fiber = next_old_fiber

		new_index = new_index + 1
	end

	if new_index == #new_children + 1 then
		-- all of the new fibers have been processed,
		-- we can safely delete the remaining old fibers
		M.delete_remaining_children(returnf, old_fiber)
		return result_first_child
	end

	if not old_fiber then
		-- we still have some new fibers to process no existing children,
		-- so we can just insert them all
		while new_index <= #new_children do
			local new_fiber = M.create_child(returnf, new_children[new_index])

			if new_fiber then
				last_placed_index = M.place_child(new_fiber, last_placed_index, new_index)

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

	local existing_children = M.map_remaining_children(old_fiber)

	while new_index <= #new_children do
		local new_fiber =
			M.update_from_map(existing_children, returnf, new_index, new_children[new_index])

		if new_fiber then
			if new_fiber.alternate then
				existing_children[new_fiber.key and new_fiber.key or new_index] = nil
			end

			last_placed_index = M.place_child(new_fiber, last_placed_index, new_index)

			if prev_new_fiber then
				prev_new_fiber.sibling = new_fiber
			else
				result_first_child = new_fiber
			end

			prev_new_fiber = new_fiber
		end

		new_index = new_index + 1
	end

	for _, child in pairs(existing_children) do
		-- delete the remaining children that are not in the new children list
		M.delete_child(returnf, child)
	end

	return result_first_child
end

---@param new_child markup.element
function M.prepare_new_child(new_child)
	local child = new_child

	while getmetatable(child) and child.typeof == "fragment" and not child.key do
		child = child.props.children
	end

	return child
end

---@param current? markup.fiber
---@param wip markup.fiber
---@param next_children markup.element
function M.reconcile_children(current, wip, next_children)
	return M.reconcile_child_fibers(wip, current and current.child, next_children)
end

---@param returnf markup.fiber
---@param current_first_child? markup.fiber
---@param new_child markup.element
function M.reconcile_child_fibers(returnf, current_first_child, new_child)
	new_child = M.prepare_new_child(new_child)

	if M.is_valid_text(new_child) then
		---@diagnostic disable-next-line: param-type-mismatch
		return M.reconcile_single_text(returnf, current_first_child, new_child)
	elseif new_child then
		if vim.islist(new_child) then
			-- this is an array list
			return M.reconcile_children_list(returnf, current_first_child, new_child)
		else
			-- this is an element object
			local el = M.prepare_element(new_child)
			if el then
				return M.reconcile_single_element(returnf, current_first_child, el)
			end
		end
	end

	return M.delete_remaining_children(returnf, current_first_child)
end

---@param current_first_child? markup.fiber
---@return table<any, markup.fiber>
function M.map_remaining_children(current_first_child)
	local existing = {}

	local child = current_first_child
	while child do
		existing[child.key or child.index] = child
		child = child.sibling
	end

	return existing
end

function M.is_node_kind(fiber)
	return fiber.tag == Tag.ELEMENT or fiber.tag == Tag.TEXT
end

---@param new_fiber markup.fiber
---@param last_placed_index integer
---@param new_index integer
function M.place_child(new_fiber, last_placed_index, new_index)
	new_fiber.index = new_index
	local current = new_fiber.alternate

	if current then
		local old_index = current.index
		if old_index < last_placed_index then
			-- TODO this is a move
			new_fiber:set_flags(Flag.PLACEMENT)
			return last_placed_index
		else
			-- this item can stay in place
			return old_index
		end
	else
		-- this is an insertion
		new_fiber:set_flags(Flag.PLACEMENT)
		return last_placed_index
	end
end

---@param returnf markup.fiber
---@param current_first_child? markup.fiber
---@param element markup.element
---@return markup.fiber?
function M.reconcile_single_element(returnf, current_first_child, element)
	local key = element.key
	local child = current_first_child

	-- iterate over existing children
	while child do
		if child.key == key then
			-- if the key matches, update the existing child
			if child.type == element.type then
				M.delete_remaining_children(returnf, child.sibling)
				local existing = M.use_fiber(child, element.props)
				existing["return"] = returnf
				return existing
			end

			M.delete_remaining_children(returnf, child)
			break
		else
			M.delete_child(returnf, child)
		end

		child = child.sibling
	end

	local created = Markup.factory.fiber.from_element(element)
	created["return"] = returnf
	return created
end

---@param fiber markup.fiber
---@param props any
function M.use_fiber(fiber, props)
	local clone = M.create_wip(fiber, props)
	clone.sibling = nil
	clone.index = 1
	return clone
end

---@param returnf markup.fiber
---@param current? markup.fiber
---@param content string|number
function M.reconcile_single_text(returnf, current, content)
	if current and current.tag == Tag.TEXT then
		-- update existing text node and delete remaining children
		M.delete_remaining_children(returnf, current.sibling)
		local existing = M.use_fiber(current, content)
		existing["return"] = returnf
		return existing
	else
		-- create a new text node and delete existing children
		M.delete_remaining_children(returnf, current)
		local fiber = Markup.factory.fiber.from_text(content)
		fiber["return"] = returnf
		fiber:set_flags(Flag.PLACEMENT)
		return fiber
	end
end

---@param payload? markup.fiber.hook
---@return markup.fiber.hook
function M.mount_wip_hook(payload)
	local hook = payload or {}

	if not M.wip_hook then
		-- first hook to be mounted
		M.wip_hook = hook
		M.current_fiber.memoized_state = hook
	else
		M.wip_hook.next = hook
		M.wip_hook = hook
	end

	return M.wip_hook
end

---@return markup.fiber.hook
function M.update_wip_hook()
	local next_current_hook

	if not M.current_hook then
		local current = M.current_fiber.alternate
		if current then
			next_current_hook = current.memoized_state
		else
			next_current_hook = nil
		end
	else
		next_current_hook = M.current_hook.next
	end

	local next_wip_hook
	if not M.wip_hook then
		next_wip_hook = M.current_fiber.memoized_state
	else
		next_wip_hook = M.wip_hook.next
	end

	if next_wip_hook then
		-- there's already a work-in-progress. Reuse it.
		M.wip_hook = next_wip_hook
		next_wip_hook = M.wip_hook.next

		M.current_hook = next_current_hook
	else
		if not next_current_hook then
			if not M.current_fiber.alternate then
				Markup.assert.bug(false, "Update hook called on initial render")
			else
				-- This is an update. We should always have a current hook.
				Markup.assert.bug(false, "Rendered more hooks than during the previous render")
			end
		end

		M.current_hook = next_current_hook

		local new_hook = { ---@type markup.fiber.hook
			typeof = M.current_hook.typeof,
			memoized_state = M.current_hook.memoized_state,
			base_state = M.current_hook.base_state,
			queue = M.current_hook.queue,
			next = nil,
		}

		if not M.wip_hook then
			-- This is the first hook in the list.
			M.wip_hook = new_hook
			M.current_fiber.memoized_state = new_hook
		else
			-- Append to the end of the list.
			M.wip_hook.next = new_hook
			M.wip_hook = new_hook
		end
	end

	return M.wip_hook
end

---@param returnf markup.fiber
---@param current_first_child? markup.fiber
function M.delete_remaining_children(returnf, current_first_child)
	local child = current_first_child

	while child do
		M.delete_child(returnf, child)
		child = child.sibling
	end
end

---@param wip markup.fiber
function M.populate_state_node(wip)
	local curr, node = wip.state_node, wip.child
	while node do
		if not (node.tag == Tag.TEXT or node.tag == Tag.ELEMENT) then
			if not node.child then
				break
			end

			node.child["return"] = node
			node = node.child
		else
			curr:append_child(node.state_node)
			node:clear_flags(Flag.PLACEMENT)

			if node == wip then
				break
			end

			while node.sibling == nil do
				if not node["return"] or node["return"] == wip then
					node = nil
					break
				end
				node = node["return"]
			end

			if node then
				node.sibling["return"] = node["return"]
				node = node.sibling
			end
		end
	end
end

---@param rootf markup.fiber
function M.commit(rootf)
	M.traverse_and_commit(rootf, rootf.child)
end

---@param hostf markup.fiber
---@param finishedf markup.fiber
function M.traverse_and_commit(hostf, finishedf)
	if not finishedf then
		return
	end

	if finishedf:check_flags(Flag.CHILD_DELETE) then
		M.commit_deletions(finishedf)
	end

	M.commit_effects(finishedf)

	if finishedf.tag == "text" or finishedf.tag == "element" then
		if finishedf:check_flags(Flag.PLACEMENT) then
			M.commit_placement(finishedf, hostf)
		end

		if finishedf:check_flags(Flag.UPDATE) then
			M.commit_update(finishedf, hostf)
		end
	else
		finishedf:reset_flags()
	end

	local child = finishedf.child
	hostf = finishedf.state_node and finishedf or hostf
	while child do
		M.traverse_and_commit(hostf, child)
		child = child.sibling
	end

	Markup.assert.bug(
		finishedf:check_flags(Flag.NONE),
		"Fiber flags must be `NONE` after commit: " .. tostring(finishedf.flags)
	)
end

---@param fiber markup.fiber
function M.is_host_parent(fiber)
	return fiber.tag == Tag.ELEMENT or fiber.tag == Tag.ROOT
end

---@param fiber markup.fiber
---@return markup.node?
function M.host_sibling(fiber)
	---@type markup.fiber
	local node = fiber

	while true do
		-- Move up if there’s no sibling
		while not node.sibling do
			local parent = node["return"]
			if not parent or M.is_host_parent(parent) then
				return nil
			end
			node = parent
		end

		node.sibling["return"] = node["return"]
		node = node.sibling

		local found = false

		while node and node.tag ~= Tag.ELEMENT and node.tag ~= Tag.TEXT do
			if node:check_flags(Flag.PLACEMENT) then
				found = true
				break
			end

			if node.child == nil then
				found = true
				break
			end

			node.child["return"] = node
			node = node.child
		end

		if not found and node and not node:check_flags(Flag.PLACEMENT) then
			return node.state_node
		end
	end
end

---@param finishedf markup.fiber
---@param parentf markup.fiber
function M.commit_placement(finishedf, parentf)
	assert(parentf, "`parentf` must exist for placement")

	local parent_node = parentf.state_node
	local sibling = M.host_sibling(finishedf)

	if sibling then
		sibling:insert_before(finishedf.state_node)
	else
		parent_node:append_child(finishedf.state_node)
	end

	finishedf:clear_flags(Flag.PLACEMENT)
end

---@param fiber markup.fiber
function M.commit_unmount(fiber)
	local hook = fiber.memoized_state

	while hook do
		local state = hook.memoized_state
		local typeof = state and state.typeof

		if typeof == "effect" then
			local inst = state.inst
			if inst.destroy then
				Markup.util.call(inst.destroy)
			end
		end

		hook = hook.next
	end
end

---@param finishedf markup.fiber
function M.commit_effects(finishedf)
	local update_queue = finishedf.update_queue
	if not update_queue then
		return
	end

	local last_effect = update_queue.last_effect
	if last_effect then
		local first_effect = last_effect.next
		local effect = first_effect ---@cast effect -nil

		repeat
			local inst = effect.inst
			if inst.destroy then
				inst.destroy()
			end
			inst.destroy = effect.create()

			effect = effect.next
		until effect == first_effect
		update_queue.last_effect = nil
	end

	assert(vim.tbl_isempty(update_queue), "`update_queue` must be empty after committing effects")
	update_queue = nil
end

---@param fiber markup.fiber
function M.commit_deletions(fiber)
	assert(fiber.deletions, "`fiber.deletions` must exist for commit deletions")

	for _, deletion in ipairs(fiber.deletions) do
		M.commit_deletion(deletion)
	end

	fiber.deletions = nil
	fiber:clear_flags(Flag.CHILD_DELETE)
end

---@param deletedf markup.fiber
function M.commit_deletion(deletedf)
	local parent = M.find_parent(deletedf)
	M.traverse_deletion(parent, deletedf, false)
	M.detach_fiber(deletedf)
end

---@param parentf markup.fiber
---@param deletedf markup.fiber
---@param did_detach boolean
function M.traverse_deletion(parentf, deletedf, did_detach)
	M.commit_unmount(deletedf)

	if not did_detach and deletedf.state_node then
		parentf.state_node:remove_child(deletedf.state_node)
		did_detach = true
	end

	local child = deletedf.child
	while child do
		M.traverse_deletion(parentf, child, did_detach)
		child = child.sibling
	end
end

function M.detach_fiber(fiber)
	local alternate = fiber.alternate
	if alternate then
		alternate["return"] = nil
	end
	fiber["return"] = nil
end

---@param finishedf markup.fiber
---@param parentf markup.fiber
function M.commit_update(finishedf, parentf)
	assert(parentf, "`parentf` must exist for placement")

	if finishedf.tag == "element" then
		if M.is_valid_text(finishedf.pending_props.children) then
			-- handle single text child elements
			if M.is_valid_text(finishedf.alternate.memoized_props.children) then
				M.update_single_text_child(finishedf)
			else
				M.place_single_text_child(finishedf)
			end
		else
			finishedf.state_node:replace_props(finishedf.pending_props)
		end
	end

	finishedf:clear_flags(Flag.UPDATE)
end

return M
