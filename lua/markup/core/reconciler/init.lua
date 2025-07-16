local log = require("markup.logger") ---@diagnostic disable-line: unused-local
local FiberTag = require("markup.core.reconciler.enum").Tag
local Flag = require("markup.core.reconciler.enum").Flag
local markup = require("markup.core")
local assertor = require("markup.assertor")
local Stack = require("markup.collection.stack")
local FiberFactory = require("markup.core.factory.fiber")
local NodeFactory = require("markup.core.factory.node")
local ElementFactory = require("markup.core.factory.element")

---@class markup.Reconciler : markup.Object
---@field currently_rendering_fiber markup.Fiber
---@field wip_hook markup.Fiber.hook?
---@field renderer? markup.Renderer
---@field dispatcher markup.Dispatcher
---@field render_scheduled boolean
---@field renderer_root markup.Renderer.Root
local Reconciler = markup.Object("markup.reconciler")

---@class markup.Reconciler.static
---@field currently_working_reconciler markup.Reconciler?
Reconciler.static = Reconciler.static

---@type markup.Reconciler?
Reconciler.static.currently_working_reconciler = nil

---@param assert_? boolean
function Reconciler.static.get(assert_)
	local reconciler = Reconciler.static.currently_working_reconciler
	if assert_ then
		assertor.bug(reconciler, "`reconciler` must be set")
	end
	return reconciler
end

---@param assert_? boolean
function Reconciler.static.get_currently_rendering_fiber(assert_)
	local reconciler = Reconciler.static.get(assert_)
	local fiber = reconciler and reconciler.currently_rendering_fiber

	if assert_ then
		assertor.bug(fiber, "`fiber` must be set")
	end

	return fiber, reconciler
end

function Reconciler:init()
	self.currently_rendering_fiber = nil
	self.dispatcher = markup.Dispatcher(self)
end

---@param root markup.Renderer.Root
function Reconciler:reconcile(root)
	Reconciler.static.currently_working_reconciler = self
	self:work_loop(root)
	Reconciler.static.currently_working_reconciler = nil
end

---@param root markup.Renderer.Root
function Reconciler:fresh_stack(root)
	local wip = self:create_wip(root.current, root.current.pending_props)

	self.work_stack = Stack:new()
	Stack.push(self.work_stack, wip)
	self.work_stack_visited = {}

	return self.work_stack
end

---dfs reconciliation
---@param root markup.Renderer.Root
function Reconciler:work_loop(root)
	self.work_stack = self:fresh_stack(root)

	local unit
	while self.work_stack.len > 0 do
		unit = Stack.pop(self.work_stack)
		self:process_unit(unit)
	end

	root.current = unit
	self.renderer_root = root
end

---@param unit markup.Fiber
---@return markup.Fiber?
function Reconciler:process_unit(unit)
	if self.work_stack_visited[unit] then
		return self:complete_unit(unit)
		-- return
	end

	self.currently_rendering_fiber = unit
	local next = self:begin_work(unit.alternate, unit)
	self.currently_rendering_fiber = nil

	unit.memoized_props = unit.pending_props

	Stack.push(self.work_stack, unit)
	Stack.push(self.work_stack, next)
	self.work_stack_visited[unit] = true
end

---@param current? markup.Fiber
---@param wip markup.Fiber
---@return markup.Fiber
function Reconciler:begin_work(current, wip)
	-- first check if the fiber can be reused
	if current then
		local old_props, new_props = current.memoized_props, wip.pending_props
		if
			current.type == wip.type
			and old_props == new_props
			and wip.flags:check(Flag.NONE)
			and not self:has_pending_updates(wip)
		then
			-- nothing to do, we can reuse the current fiber
			return self:bailout(wip)
		end
	end

	local next_work ---@type function
	if wip.tag == FiberTag.ELEMENT then
		next_work = Reconciler.update_element_component
	elseif wip.tag == FiberTag.FUNCTION then
		next_work = Reconciler.update_function_component
	elseif wip.tag == FiberTag.TEXT then
		next_work = Reconciler.update_text_component
	elseif wip.tag == FiberTag.FRAGMENT then
		next_work = Reconciler.update_fragment_component
	elseif wip.tag == FiberTag.ROOT then
		next_work = Reconciler.update_root_component
	else
		error(("Invalid Fiber tag: %s"):format(wip.tag))
	end

	---@diagnostic disable-next-line: return-type-mismatch
	return next_work(self, current, wip)
end

---@param unit markup.Fiber
function Reconciler:complete_unit(unit)
	local current, wip = unit.alternate, unit

	local complete_work ---@type function
	if wip.tag == FiberTag.ELEMENT then
		complete_work = Reconciler.complete_element_component
	elseif wip.tag == FiberTag.TEXT then
		complete_work = Reconciler.complete_text_component
	elseif wip.tag == FiberTag.FUNCTION then
		complete_work = Reconciler.complete_function_component
	elseif wip.tag == FiberTag.CLASS then
		complete_work = Reconciler.complete_class_component
	elseif wip.tag == FiberTag.FRAGMENT then
		complete_work = Reconciler.complete_fragment_component
	elseif wip.tag == FiberTag.ROOT then
		complete_work = Reconciler.complete_root_component
	else
		error(("Invalid Fiber tag: %s"):format(wip.tag))
	end
	-- complete_work(self, current, wip)

	Stack.push(self.work_stack, unit.sibling)
	-- assertor.bug(unit.flags:check(Flag.NONE), "Fiber flags must be `NONE` after completion")
end

---@param fiber markup.Fiber
---@return markup.Fiber
function Reconciler:find_element_ancestor(fiber)
	local parent = fiber and fiber["return"]

	while parent and not parent.state_node do
		parent = parent["return"]
	end

	assertor.bug(parent, "Element ancestor must exist")
	return parent
end

---@param fiber markup.Fiber
function Reconciler:traverse_deletions(fiber)
	local bfs = Stack.new()
	Stack.push(bfs, fiber)

	while bfs.len > 0 do
		local node = Stack.pop(bfs)

		if node.state_node then
			node.state_node:destroy()
		else
			local child = node.child
			while child do
				Stack.push(bfs, child)
				child = child.sibling
			end
		end
	end
end

---@param fiber markup.Fiber
function Reconciler:process_deletions(fiber)
	if not fiber.deletions then
		return
	end
	assertor.bug(fiber.deletions, "`fiber.deletions` must exist for processing deletions")

	for _, deletion in ipairs(fiber.deletions) do
		self:traverse_deletions(deletion)
	end

	fiber.deletions = nil
	fiber.flags:clear(Flag.CHILD_DELETE)
end

---@param wip markup.Fiber
function Reconciler:place_single_node(wip)
	wip.state_node = NodeFactory.create_from_fiber(wip)

	if self:is_valid_text(wip.pending_props.children) then
		self:place_single_text_child(wip)
	end

	wip.hostf.state_node:append_child(wip.state_node)
	wip.flags:clear(Flag.PLACEMENT)
end

---@param wip markup.Fiber
function Reconciler:update_single_node(wip)
	local current = wip.alternate
	assert(current, "`current` must exist for updating a single node")

	if self:is_valid_text(wip.pending_props.children) then
		-- handle single text child elements
		if self:is_valid_text(current.memoized_props.children) then
			self:update_single_text_child(wip)
		else
			self:place_single_text_child(wip)
		end
	else
		wip.state_node:replace_props(wip.pending_props)
	end

	wip.flags:clear(Flag.UPDATE)
end

---@param fiber markup.Fiber
function Reconciler:place_single_text_child(fiber)
	assert(fiber.state_node, "`fiber.state_node` must exist for text child placement")

	local text_node = NodeFactory.create_from_text(fiber.pending_props.children)
	fiber.state_node:append_child(text_node)
end

---@param fiber markup.Fiber
function Reconciler:bailout(fiber)
	self:clone_child_fibers(fiber)
	return fiber.child
end

---@param current? markup.Fiber
---@param wip markup.Fiber
function Reconciler:update_function_component(current, wip)
	local next_children = self:render_with_hooks(current, wip)

	wip.child = self:reconcile_children(current, wip, next_children)
	return wip.child
end

function Reconciler:update_fragment_component(current, wip)
	wip.child = self:reconcile_children(current, wip, wip.pending_props.children)
	return wip.child
end

---@param current markup.Fiber
---@param wip markup.Fiber
function Reconciler:update_root_component(current, wip)
	assertor.bug(current, "Root must always have an alternate fiber")

	wip.child = self:reconcile_children(current, wip, wip.pending_props.children)
	return wip.child
end

---@param current? markup.Fiber
---@param wip markup.Fiber
function Reconciler:update_text_component(current, wip)
	if not current then
		wip.flags:set(Flag.PLACEMENT)
	elseif current.memoized_props ~= wip.pending_props then
		wip.flags:set(Flag.UPDATE)
	end
end

---@param fiber markup.Fiber
function Reconciler:create_instance(fiber)
	assertor.bug(not fiber.state_node, "`fiber.state_node` must not exist during creation")

	fiber.flags:set(Flag.PLACEMENT)

	-- if fiber.tag == FiberTag.FUNCTION then
	-- 	fiber.state_node = fiber.type(fiber.pending_props)
	-- elseif fiber.tag == FiberTag.ELEMENT then
	-- 	-- fiber.state_node =
	-- elseif fiber.tag == FiberTag.ROOT then
	-- end
	-- fiber.state_node.frame = self.renderer

	return fiber
end

function Reconciler:is_direct_text_child(fiber)
	local parent = fiber["return"]
	return parent and parent.tag == FiberTag.ELEMENT
end

---@param current? markup.Fiber
---@param wip markup.Fiber
function Reconciler:update_element_component(current, wip)
	local next_props = wip.pending_props
	local next_children = next_props and next_props.children

	if not current then
		wip.flags:set(Flag.PLACEMENT)
	elseif wip.state_node and current.memoized_props ~= wip.pending_props then
		wip.flags:set(Flag.UPDATE)
	end

	if self:is_valid_text(next_children) then
		-- dont return, keep the function going to delete the remaining children
		next_children = nil
	end

	wip.child = self:reconcile_children(current, wip, next_children)
	return wip.child
end

---@param fiber markup.Fiber
function Reconciler:has_pending_updates(fiber)
	if fiber.tag ~= "function" then
		return false
	end

	local hook = fiber.memoized_state
	while hook do
		if hook.queue and hook.queue.pending then
			return true
		end
		hook = hook.next
	end
	return false
end

---@param current? markup.Fiber
---@param wip markup.Fiber
function Reconciler:render_with_hooks(current, wip)
	-- clear the hooks to make space for the next hooks
	self.wip_hook = nil

	-- if there are pending updates, update the state
	self.dispatcher:resolve_hook_updates(wip)

	local Component = wip.type
	local props = wip.pending_props
	local children = Component(props) -- re-render the component

	wip.memoized_state = wip.hook
	wip.hook = nil

	wip.flags:clear(Flag.UPDATE)

	return children
end

---@param returnf markup.Fiber
---@param child markup.Fiber
function Reconciler:delete_child(returnf, child)
	-- if not child.state_node then
	-- 	return
	-- end

	if not returnf.deletions then
		returnf.deletions = { child }
		returnf.flags:set(Flag.CHILD_DELETE)
	else
		table.insert(returnf.deletions, child)
	end
end

---@param returnf markup.Fiber
---@param child markup.Element
function Reconciler:create_child(returnf, child)
	if self:is_valid_text(child) then
		local fiber = FiberFactory.create_from_text(child) ---@diagnostic disable-line: param-type-mismatch
		fiber["return"] = returnf
		return fiber
	end

	if child then
		local el = self:prepare_element(child)
		if el then
			local fiber = FiberFactory.create_from_element(el)
			fiber["return"] = returnf
			return fiber
		end
	end

	return nil
end

---@param content any
function Reconciler:is_valid_text(content)
	return (type(content) == "string" and content ~= "") or type(content) == "number"
end

---@param content any
function Reconciler:should_be_fragment(content)
	return type(content) == "table" and not getmetatable(content) and not vim.tbl_isempty(content)
end

---@param element markup.Element
function Reconciler:is_host_element(element)
	if not getmetatable(element) then
		return false
	end ---@cast element markup.Element
	return type(element.type) == "string"
end

---@param content any
function Reconciler:is_valid_element(content)
	if not getmetatable(content) then
		return false
	end ---@cast content markup.Element

	if self:is_host_element(content) then
		local children = content.props.children
		if not children or (type(children) == "table" and vim.tbl_isempty(children)) then
			return false
		end
	end

	return true
end

---@param returnf markup.Fiber
---@param old_fiber? markup.Fiber
---@param new_child markup.Element
function Reconciler:update_slot(returnf, old_fiber, new_child)
	local key = old_fiber and old_fiber.key

	if self:is_valid_text(new_child) then
		if key then
			return nil
		end

		return self:update_text_node(returnf, old_fiber, new_child)
	end

	if new_child and new_child.key == key then
		local el = self:prepare_element(new_child)
		if el then
			return self:update_element_node(returnf, old_fiber, el)
		end
	end

	return nil
end

---@param fiber markup.Fiber
function Reconciler:clone_child_fibers(fiber)
	if not fiber.child then
		return nil
	end

	---@type markup.Fiber
	local current_child = fiber.child

	local new_child = self:create_wip(current_child, current_child.pending_props)
	fiber.child = new_child
	new_child["return"] = fiber

	while current_child ~= nil and current_child.sibling ~= nil do
		current_child = current_child.sibling

		new_child.sibling = self:create_wip(current_child, current_child.pending_props)
		new_child = new_child.sibling

		new_child["return"] = fiber
	end

	new_child.sibling = nil
end

---@param current markup.Fiber
---@param props any
function Reconciler:create_wip(current, props)
	local wip = current.alternate

	if not wip then
		wip = FiberFactory.create(current.tag, props, current.key)
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
	wip.hook = current.hook
	wip.sibling = current.sibling
	wip.index = current.index
	wip.__id = current.__id

	return wip
end

function Reconciler:prepare_element(element)
	if not element then
		return nil
	end

	local el = element
	if self:should_be_fragment(el) then
		el = ElementFactory.create_fragment(el)
	end

	return self:is_valid_element(el) and el
end

---@param existing table<any, markup.Fiber>
---@param returnf markup.Fiber
---@param new_index integer
---@param new_child markup.Element
function Reconciler:update_from_map(existing, returnf, new_index, new_child)
	if self:is_valid_text(new_child) then
		local matched = existing[new_index]
		return self:update_text_node(returnf, matched, new_child)
	end

	if new_child then
		local el = self:prepare_element(new_child)
		if el then
			local matched = existing[el.key or new_index]
			return self:update_element_node(returnf, matched, el)
		end
	end

	return nil
end

---@param returnf markup.Fiber
---@param current? markup.Fiber
---@param content any
function Reconciler:update_text_node(returnf, current, content)
	if current and current.tag == FiberTag.TEXT then
		-- If the existing fiber is a text node, update it
		local existing = self:use_fiber(current, content)
		existing["return"] = returnf
		return existing
	else
		-- Create a new text node
		local fiber = FiberFactory.create_from_text(content)
		fiber["return"] = returnf
		return fiber
	end
end

---@param fiber markup.Fiber
function Reconciler:update_node_text(fiber)
	local old_text, new_text = fiber.alternate.pending_props, fiber.pending_props
	local node = fiber.state_node

	if old_text ~= new_text then
		node:set_text_content(new_text)
		fiber.flags:clear(Flag.UPDATE)
	end
end

---@param fiber markup.Fiber
function Reconciler:update_single_text_child(fiber)
	local text_node = fiber.state_node.child_nodes[1]
	assert(text_node:is("text"))

	text_node:set_text_content(fiber.pending_props.children)
end

---@param returnf markup.Fiber
---@param current? markup.Fiber
---@param element markup.Element
function Reconciler:update_element_node(returnf, current, element)
	if current and current.type == element.type then
		-- If the existing fiber is not an element node, create a new one
		local existing = self:use_fiber(current, element.props)
		existing["return"] = returnf
		return existing
	else
		-- Create a new element node
		local fiber = FiberFactory.create_from_element(element)
		fiber["return"] = returnf
		return fiber
	end
end

---@param returnf markup.Fiber
---@param current_first_child? markup.Fiber
---@param new_children markup.Element[]
function Reconciler:reconcile_children_list(returnf, current_first_child, new_children)
	local new_index, last_placed_index = 1, 1

	new_children = vim.tbl_filter(function(i)
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

		local new_fiber = self:update_slot(returnf, old_fiber, new_children[new_index])

		if not new_fiber then
			if not old_fiber then
				old_fiber = next_old_fiber
			end
			break
		end

		if old_fiber and not new_fiber.alternate then
			self:delete_child(returnf, old_fiber)
		end

		last_placed_index = self:place_child(new_fiber, last_placed_index, new_index)

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
		self:delete_remaining_children(returnf, old_fiber)
		return result_first_child
	end

	if not old_fiber then
		-- we still have some new fibers to process no existing children,
		-- so we can just insert them all
		while new_index <= #new_children do
			local new_fiber = self:create_child(returnf, new_children[new_index])

			if new_fiber then
				last_placed_index = self:place_child(new_fiber, last_placed_index, new_index)

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

	local existing_children = self:map_remaining_children(returnf, old_fiber)

	while new_index <= #new_children do
		local new_fiber =
			self:update_from_map(existing_children, returnf, new_index, new_children[new_index])

		if new_fiber then
			last_placed_index = self:place_child(new_fiber, last_placed_index, new_index)

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

function Reconciler:prepare_new_child(new_child)
	local child = new_child

	while getmetatable(child) and child.typeof == "fragment" and not child.key do
		child = child.props.children
	end

	return child
end

---@param current? markup.Fiber
---@param wip markup.Fiber
---@param next_children markup.Element
function Reconciler:reconcile_children(current, wip, next_children)
	return self:reconcile_child_fibers(wip, current and current.child, next_children)
end

---@param returnf markup.Fiber
---@param current_first_child? markup.Fiber
---@param new_child markup.Element
function Reconciler:reconcile_child_fibers(returnf, current_first_child, new_child)
	new_child = self:prepare_new_child(new_child)

	if self:is_valid_text(new_child) then
		---@diagnostic disable-next-line: param-type-mismatch
		return self:reconcile_single_text(returnf, current_first_child, new_child)
	elseif new_child then
		if not getmetatable(new_child) then
			-- this is an array list
			return self:reconcile_children_list(returnf, current_first_child, new_child)
		else
			-- this is an element object
			local el = self:prepare_element(new_child)
			if el then
				return self:reconcile_single_element(returnf, current_first_child, el)
			end
		end
	end

	return self:delete_remaining_children(returnf, current_first_child)
end

---@param returnf markup.Fiber
---@param current_first_child? markup.Fiber
---@return table<any, markup.Fiber>
function Reconciler:map_remaining_children(returnf, current_first_child)
	local existing = {}

	local child = current_first_child
	while child do
		existing[child.key or child.index] = child
		child = child.sibling
	end

	return existing
end

function Reconciler:is_node_kind(fiber)
	return fiber.tag == FiberTag.ELEMENT or fiber.tag == FiberTag.TEXT
end

---@param new_fiber markup.Fiber
---@param last_placed_index integer
---@param new_index integer
function Reconciler:place_child(new_fiber, last_placed_index, new_index)
	new_fiber.index = new_index
	local current = new_fiber.alternate

	if current then
		local old_index = current.index
		if old_index < last_placed_index then
			-- this is a move
			new_fiber.flags:set(Flag.PLACEMENT)
			return last_placed_index
		else
			-- this item can stay in place
			return old_index
		end
	else
		-- this is an insertion
		new_fiber.flags:set(Flag.PLACEMENT)
		return last_placed_index
	end
end

---@param returnf markup.Fiber
---@param current_first_child? markup.Fiber
---@param element markup.Element
---@return markup.Fiber?
function Reconciler:reconcile_single_element(returnf, current_first_child, element)
	local key = element.key
	local child = current_first_child

	-- iterate over existing children
	while child do
		if child.key == key then
			-- if the key matches, update the existing child
			if child.type == element.type then
				local existing = self:use_fiber(child, element.props)
				existing["return"] = returnf
				return existing
			end

			self:delete_remaining_children(returnf, child)
			break
		else
			self:delete_child(returnf, child)
		end

		child = child.sibling
	end

	local created = FiberFactory.create_from_element(element)
	created["return"] = returnf
	return created
end

---@param fiber markup.Fiber
---@param props any
function Reconciler:use_fiber(fiber, props)
	local clone = self:create_wip(fiber, props)
	clone.sibling = nil
	clone.index = 1
	return clone
end

---@param returnf markup.Fiber
---@param current? markup.Fiber
---@param content string|number
function Reconciler:reconcile_single_text(returnf, current, content)
	if current and current.tag == FiberTag.TEXT then
		-- update existing text node and delete remaining children
		self:delete_remaining_children(returnf, current.sibling)
		local existing = self:use_fiber(current, content)
		existing["return"] = returnf
		return existing
	else
		-- create a new text node and delete existing children
		self:delete_remaining_children(returnf, current)
		local fiber = FiberFactory.create_from_text(content)
		fiber["return"] = returnf
		fiber.flags:set(Flag.PLACEMENT)
		return fiber
	end
end

---@param payload? table
---@return markup.Fiber.hook
function Reconciler:mount_wip_hook(payload)
	local hook = payload or {}

	if not self.wip_hook then
		-- first hook to be mounted
		self.wip_hook = hook
		self.currently_rendering_fiber.hook = hook
	else
		self.wip_hook.next = hook
		self.wip_hook = hook
	end

	return self.wip_hook
end

---@return markup.Fiber.hook
function Reconciler:update_wip_hook()
	if not self.wip_hook then
		-- first hook to be updated
		self.wip_hook = self.currently_rendering_fiber.memoized_state
		self.currently_rendering_fiber.hook = self.wip_hook
	end

	local hook = self.wip_hook
	self.wip_hook = self.wip_hook.next

	assertor.hook_user(hook, "Rendered more hooks than on previous render") ---@cast hook -nil
	return hook
end

---@param returnf markup.Fiber
---@param current_first_child? markup.Fiber
function Reconciler:delete_remaining_children(returnf, current_first_child)
	local child = current_first_child

	while child do
		self:delete_child(returnf, child)
		child = child.sibling
	end
end

---@param current markup.Fiber
---@param wip markup.Fiber
function Reconciler:complete_root_component(current, wip)
	if wip.flags:check(Flag.PLACEMENT) then
		self:populate_state_node(wip)
		wip.flags:clear(Flag.PLACEMENT)
	end
end

---@param wip markup.Fiber
function Reconciler:populate_state_node(wip)
	local curr, node = wip.state_node, wip.child
	while node do
		if not (node.tag == FiberTag.TEXT or node.tag == FiberTag.ELEMENT) then
			if not node.child then
				break
			end

			node.child["return"] = node
			node = node.child
		else
			curr:append_child(node.state_node)

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

---@param current markup.Fiber
---@param wip markup.Fiber
function Reconciler:complete_function_component(current, wip)
	-- function component placemenet is handled
	-- during `begin_work`
	wip.flags:clear(Flag.PLACEMENT)

	-- if wip.flags:check(Flag.CHILD_DELETE) then
	-- 	self:process_deletions(wip)
	-- end
end

---@param current markup.Fiber
---@param wip markup.Fiber
function Reconciler:complete_component_component(current, wip)
	--
end

---@param current markup.Fiber
---@param wip markup.Fiber
function Reconciler:complete_text_component(current, wip)
	if wip.flags:check(Flag.PLACEMENT) then
		self:place_single_node(wip)
	end

	if wip.flags:check(Flag.UPDATE) then
		self:update_node_text(wip)
	end
end

---@param current markup.Fiber
---@param wip markup.Fiber
function Reconciler:complete_element_component(current, wip)
	if wip.flags:check(Flag.CHILD_DELETE) then
		self:process_deletions(wip)
	end

	if wip.flags:check(Flag.PLACEMENT) then
		self:place_single_node(wip)
		-- self:populate_state_node(wip)
	end

	if wip.flags:check(Flag.UPDATE) then
		self:update_single_node(wip)
	end
end

---@param current markup.Fiber
---@param wip markup.Fiber
function Reconciler:complete_class_component(current, wip)
	--
end

---@param current markup.Fiber
---@param wip markup.Fiber
function Reconciler:complete_fragment_component(current, wip)
	--
end

---@param rootf markup.Fiber
function Reconciler:commit(rootf)
	self:traverse_and_commit(rootf, rootf.child)
end

---@param hostf markup.Fiber
---@param fiber markup.Fiber
function Reconciler:traverse_and_commit(hostf, fiber)
	if not fiber then
		return
	end
	-- handle fiber with `state_node`

	fiber.hostf = hostf
	local complete_work ---@type function
	if fiber.tag == FiberTag.ELEMENT then
		complete_work = Reconciler.complete_element_component
	elseif fiber.tag == FiberTag.TEXT then
		complete_work = Reconciler.complete_text_component
	elseif fiber.tag == FiberTag.FUNCTION then
		complete_work = Reconciler.complete_function_component
	elseif fiber.tag == FiberTag.CLASS then
		complete_work = Reconciler.complete_class_component
	elseif fiber.tag == FiberTag.FRAGMENT then
		complete_work = Reconciler.complete_fragment_component
	elseif fiber.tag == FiberTag.ROOT then
		complete_work = Reconciler.complete_root_component
	else
		error(("Invalid Fiber tag: %s"):format(fiber.tag))
	end
	complete_work(self, fiber.alternate, fiber)

	self:process_deletions(fiber)

	hostf = fiber.state_node and fiber or hostf

	local child = fiber.child
	while child do
		self:traverse_and_commit(hostf, child)
		child = child.sibling
	end
end

function Reconciler:schedule_render()
	if self.render_scheduled then
		return
	end

	self.render_scheduled = true
	vim.schedule(function()
		self.render_scheduled = false
		self.renderer_root.owner:rerender()
	end)
end

---@alias markup.Reconciler.constructor
---| fun(): markup.Reconciler
---| { static: markup.Reconciler.static }
---| markup.Reconciler.static

---@type markup.Reconciler.constructor
return Reconciler
