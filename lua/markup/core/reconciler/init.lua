local log = require("markup.logger") ---@diagnostic disable-line: unused-local
local FiberTag = require("markup.core.reconciler.enum").Tag
local FiberFlag = require("markup.core.reconciler.enum").Flag
local markup = require("markup.core")
local assertor = require("markup.assertor")
local Stack = require("markup.collection.stack")

---@class markup.Reconciler : markup.Object
---@field currently_rendering_fiber markup.Fiber
---@field wip_hook markup.Fiber.hook?
---@field dispatcher markup.Dispatcher
---@field renderer markup.Renderer
---@field render_scheduled boolean
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

---@param renderer markup.Renderer
function Reconciler:init(renderer)
	self.currently_rendering_fiber = nil
	self.renderer = renderer
	self.dispatcher = markup.Dispatcher(self)
end

---@return markup.Renderer.Root
function Reconciler:root()
	return self.renderer.root
end

---@return markup.Fiber
function Reconciler:reconcile()
	Reconciler.static.currently_working_reconciler = self
	self:work_loop()
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

-- dfs reconciliation
function Reconciler:work_loop()
	self.work_stack = self:fresh_stack(self.renderer.root)

	local unit
	while self.work_stack.len > 0 do
		unit = Stack.pop(self.work_stack)
		self:process_unit(unit)
	end

	self.renderer.root.current = unit
end

---@param unit markup.Fiber
---@return markup.Fiber?
function Reconciler:process_unit(unit)
	if self.work_stack_visited[unit] then
		return self:complete_unit(unit)
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
			and FiberFlag.check(wip, FiberFlag.NONE)
			and not self:has_pending_updates(wip)
		then
			-- nothing to do,
			-- we can reuse the current fiber
			return self:bailout(wip)
		end
	end

	local next_work ---@type function
	if wip.tag == FiberTag.FUNCTION then
		next_work = Reconciler.update_function_component
	elseif wip.tag == FiberTag.ELEMENT then
		next_work = Reconciler.update_element_component
	elseif wip.tag == FiberTag.TEXT then
		next_work = Reconciler.update_text_component
	elseif wip.tag == FiberTag.ROOT then
		next_work = Reconciler.update_root_component
	elseif wip.tag == FiberTag.FRAGMENT then
		next_work = Reconciler.update_fragment_component
	else
		error(("Invalid Fiber tag: %s"):format(wip.tag))
	end

	---@diagnostic disable-next-line: return-type-mismatch
	return next_work(self, current, wip)
end

---@param unit markup.Fiber
function Reconciler:complete_unit(unit)
	local current, wip = unit.alternate, unit

	markup.Switch(wip.tag, {
		[FiberTag.FUNCTION] = function()
			-- function component placemenet is handled
			-- during `begin_work`
			FiberFlag.clear(wip, FiberFlag.PLACEMENT)
		end,
		[FiberTag.FRAGMENT] = function()
			-- nothing to do
		end,
		[FiberTag.ELEMENT] = function()
			if FiberFlag.check(wip, FiberFlag.PLACEMENT) then
				self:place_single_child(wip)
			end

			if FiberFlag.check(wip, FiberFlag.DELETE) then
				self:process_deletions(wip)
			end

			-- TODO update node props
			-- simple implementation for now
			if wip.state_node and wip.memoized_props then
				wip.state_node:set_props(wip.memoized_props)
			end
		end,
		[FiberTag.ROOT] = function()
			-- self:place_single_child(fiber)
			if FiberFlag.check(wip, FiberFlag.DELETE) then
				self:process_deletions(wip)
			end
		end,
		[FiberTag.TEXT] = function()
			if FiberFlag.check(wip, FiberFlag.PLACEMENT) then
				self:place_single_child(wip)
			end

			if current then
				self:update_node_text(wip)
			end
		end,

		["default"] = function()
			error(("Invalid Fiber tag: %s"):format(wip.tag))
		end,
	})

	Stack.push(self.work_stack, unit.sibling)
	assertor.bug(
		FiberFlag.check(unit, FiberFlag.NONE),
		"Fiber flags must be `NONE` after completion"
	)
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

function Reconciler:process_deletions(fiber)
	for _, deletion in ipairs(fiber.deletions) do
		fiber.state_node:remove_child(deletion.state_node)
	end
	fiber.deletions = nil
	FiberFlag.clear(fiber, FiberFlag.DELETE)
end

---@param fiber markup.Fiber
function Reconciler:place_single_child(fiber)
	assertor.bug(fiber.state_node, "`fiber.state_node` must exist during placement")

	local node = fiber.state_node
	local parent = self:find_element_ancestor(fiber)
	parent.state_node:append_child(node)
	FiberFlag.clear(fiber, FiberFlag.PLACEMENT)
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
	return nil
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
	if not (current and current.state_node) then
		self:create_instance(wip)
	end
end

function Reconciler:create_instance(fiber)
	assertor.bug(not fiber.state_node, "`fiber.state_node` must not exist during creation")

	FiberFlag.set(fiber, FiberFlag.PLACEMENT)
	local node = fiber.type(fiber.pending_props)
	fiber.state_node = node
	fiber.state_node.frame = self.renderer

	return fiber
end

---@param current? markup.Fiber
---@param wip markup.Fiber
function Reconciler:update_element_component(current, wip)
	-- local prev_props = current and current.memoized_props
	local next_props = wip.pending_props
	local next_children = next_props and next_props.children
	local prev_props = current and current.memoized_props

	if not (current and current.state_node) then
		self:create_instance(wip)
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

	FiberFlag.clear(wip, FiberFlag.UPDATE)

	return children
end

---@param returnf markup.Fiber
---@param child markup.Fiber
function Reconciler:delete_child(returnf, child)
	local parent = self:find_element_ancestor(child)

	if not parent.deletions then
		parent.deletions = { child }
		FiberFlag.set(parent, FiberFlag.DELETE)
	else
		table.insert(parent.deletions, child)
	end
end

---@param returnf markup.Fiber
---@param child markup.xElement
function Reconciler:create_child(returnf, child)
	if self:valid_text(child) then
		local fiber = markup.create_fiber_from_text(child) ---@diagnostic disable-line: param-type-mismatch
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

---@param element markup.xElement
function Reconciler:valid_text(element)
	return (type(element) == "string" and element ~= "") or type(element) == "number"
end

---@param returnf markup.Fiber
---@param old_fiber? markup.Fiber
---@param new_child markup.xElement
function Reconciler:update_slot(returnf, old_fiber, new_child)
	local key = old_fiber and old_fiber.key

	if self:valid_text(new_child) then
		if key then
			return nil
		end

		---@diagnostic disable-next-line: param-type-mismatch
		return self:update_text_node(returnf, old_fiber, new_child)
	end

	if new_child then
		if vim.islist(new_child) then
			-- TODO handle fragments
		elseif new_child.key == key then
			return self:update_element_node(returnf, old_fiber, new_child)
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
		wip = markup.create_fiber(current.type, props, current.key)
		wip.tag = current.tag
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

	return wip
end

---@param existing table<any, markup.Fiber>
---@param returnf markup.Fiber
---@param new_index integer
---@param new_child markup.xElement
function Reconciler:update_from_map(existing, returnf, new_index, new_child)
	if (type(new_child) == "string" and new_child ~= "") or type(new_child) == "number" then
		local matched = existing[new_index]
		return self:update_text_node(returnf, matched, new_child)
	end

	if new_child.type then
		local matched = existing[new_child.key or new_index]
		return self:update_element_node(returnf, matched, new_child)
	end

	return nil
end

---@param returnf markup.Fiber
---@param current? markup.Fiber
---@param content string
function Reconciler:update_text_node(returnf, current, content)
	if current and current.tag == FiberTag.TEXT then
		-- If the existing fiber is a text node, update it
		local existing = self:use_fiber(current, content)
		existing["return"] = returnf
		return existing
	else
		-- Create a new text node
		local fiber = markup.create_fiber_from_text(content)
		fiber["return"] = returnf
		return fiber
	end
end

---@param fiber markup.Fiber
function Reconciler:update_node_text(fiber)
	local old_text, new_text = fiber.alternate.pending_props, fiber.pending_props
	local node = fiber.state_node ---@cast node markup.Text

	if old_text ~= new_text then
		node:set(new_text)
	end
end

---@param returnf markup.Fiber
---@param current? markup.Fiber
---@param element markup.xElement
function Reconciler:update_element_node(returnf, current, element)
	if current and current.type == element.type then
		-- If the existing fiber is not an element node, create a new one
		local existing = self:use_fiber(current, element.props)
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
function Reconciler:reconcile_children_list(returnf, current_first_child, new_children)
	local new_index, last_placed_index = 1, 1

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

	local xd = 5

	if new_index == #new_children + 1 then
		self:delete_remaining_children(returnf, old_fiber)
		return result_first_child
	end

	if not old_fiber then
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

---@param current? markup.Fiber
---@param wip markup.Fiber
---@param next_children markup.xElement
function Reconciler:reconcile_children(current, wip, next_children)
	return self:reconcile_child_fibers(wip, current and current.child, next_children)
end

---@param returnf markup.Fiber
---@param current_first_child? markup.Fiber
---@param new_child markup.xElement
function Reconciler:reconcile_child_fibers(returnf, current_first_child, new_child)
	if self:valid_text(new_child) then
		---@diagnostic disable-next-line: param-type-mismatch
		return self:reconcile_single_text(returnf, current_first_child, new_child)
	end

	if vim.islist(new_child) then
		return self:reconcile_children_list(returnf, current_first_child, new_child)
	elseif type(new_child) == "table" then
		return self:reconcile_single_element(returnf, current_first_child, new_child)
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
			FiberFlag.set(new_fiber, FiberFlag.PLACEMENT)
			return last_placed_index
		else
			-- this is can stay in place
			return old_index
		end
	else
		-- this is an insertion
		FiberFlag.set(new_fiber, FiberFlag.PLACEMENT)
		return last_placed_index
	end
end

---@param returnf markup.Fiber
---@param current_first_child? markup.Fiber
---@param element markup.xElement
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

	local created = markup.create_fiber_from_element(element)
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
		local fiber = markup.create_fiber_from_text(content)
		fiber["return"] = returnf
		FiberFlag.set(fiber, FiberFlag.PLACEMENT)
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

function Reconciler:schedule_render()
	if self.render_scheduled then
		return
	end

	self.render_scheduled = true
	vim.schedule(function()
		self.render_scheduled = false
		self.renderer:rerender()
	end)
end

---@param f? markup.Fiber
function Reconciler:print(f)
	local lines = {}

	---@param fiber markup.Fiber
	local function print_fiber_tree(fiber, depth)
		if not fiber then
			return
		end

		local indent = ("\t"):rep(depth or 0)

		local line = (indent .. ("Fiber: %s (%s)"):format(fiber.type, fiber.tag))
		table.insert(lines, line)

		if fiber.child then
			print_fiber_tree(fiber.child, (depth or 0) + 1)
		end

		if fiber.sibling then
			print_fiber_tree(fiber.sibling, depth)
		end
	end

	print_fiber_tree(f or self.renderer.root.current, 0)
	log.debug(table.concat(lines, "\n"))

	return lines
end

---@alias markup.Reconciler.constructor
---| fun(renderer: markup.Renderer): markup.Reconciler
---| { static: markup.Reconciler.static }
---| markup.Reconciler.static

---@type markup.Reconciler.constructor
return Reconciler
