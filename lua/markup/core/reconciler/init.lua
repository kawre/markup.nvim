local log = require("markup.logger") ---@diagnostic disable-line: unused-local
local FiberTag = require("markup.core.reconciler.enum").Tag
local FiberFlag = require("markup.core.reconciler.enum").Flag
local markup = require("markup.core")

---@class markup.Reconciler : markup.Object
---@field currently_rendering_fiber markup.Fiber?
---@field wip_hook markup.Fiber.hook?
---@field dispatcher markup.Dispatcher
---@field renderer markup.Renderer
local Reconciler = markup.Object("markup.reconciler")

---@class markup.Reconciler.static
---@field currently_working_reconciler markup.Reconciler?
---@field get_currently_rendering_fiber fun(): markup.Fiber?
Reconciler.static = Reconciler.static

---@type markup.Reconciler?
Reconciler.static.currently_working_reconciler = nil

function Reconciler.static.get_currently_rendering_fiber()
	local current_reconciler = Reconciler.static.currently_working_reconciler
	return current_reconciler and current_reconciler.currently_rendering_fiber
end

function Reconciler.static.get()
	return Reconciler.static.currently_working_reconciler
end

---@param renderer markup.Renderer
function Reconciler:init(renderer)
	self.currently_rendering_fiber = nil
	self.update_queue = markup.Array()
	self.work_stack = markup.Array()
	self.renderer = renderer
	self.dispatcher = markup.Dispatcher(self)
end

---@return markup.Renderer.Root
function Reconciler:root()
	return self.renderer.root
end

---@return markup.Fiber
function Reconciler:reconcile()
	log.info("reconcile")

	Reconciler.static.currently_working_reconciler = self
	self:work_loop()
	Reconciler.static.currently_working_reconciler = nil
end

---@param root markup.Renderer.Root
function Reconciler:fresh_stack(root)
	self.work_stack = markup.Array()
	self.work_stack_visited = {}

	local wip = self:create_wip(root.current, root.current.pending_props)
	self.work_stack:push(wip)
	root.current = wip

	return self.work_stack
end

-- Bottom-up reconciliation
function Reconciler:work_loop()
	self.work_stack = self:fresh_stack(self.renderer.root)

	while #self.work_stack > 0 do
		local unit = self.work_stack:pop()
		local next = self:process(unit)

		if next then
			self.work_stack:push(next)
		end

		self.work_stack_visited[unit] = true
	end
end

---@param unit markup.Fiber
---@return markup.Fiber?
function Reconciler:process(unit)
	if self.work_stack_visited[unit] then
		-- Fiber has already been processed,
		-- complete the work and return
		self:complete_work(unit)
		return nil
	end

	-- Push the current fiber and its sibling to the stack
	-- to be processed after all descendants have been processed (bottom-up)
	self.work_stack:push(unit, unit.sibling)

	self.currently_rendering_fiber = unit
	local next = self:begin_work(unit.alternate, unit)
	self.currently_rendering_fiber = nil
	unit.memoized_props = unit.pending_props

	return next
end

---@param current? markup.Fiber
---@param wip markup.Fiber
---@return markup.Fiber
function Reconciler:begin_work(current, wip)
	-- first check if the fiber can be reused
	if current then
		local old_props, new_props = current.memoized_props, wip.pending_props

		if current.type == wip.type and vim.deep_equal(old_props, new_props) then
			-- If the props and type are the same,
			-- we can reuse the current fiber
			if not FiberFlag.check(wip, FiberFlag.UPDATE) then
				wip.flags = FiberFlag.NONE
				return self:bailout(wip)
			end
		else
			FiberFlag.set(wip, FiberFlag.UPDATE)
		end
	else
		FiberFlag.set(wip, FiberFlag.PLACEMENT)
	end

	local next_work = markup.Switch(wip.tag, {
		[FiberTag.FUNCTION] = Reconciler.update_function_component,
		[FiberTag.FRAGMENT] = Reconciler.update_fragment_component,
		[FiberTag.ELEMENT] = Reconciler.update_element_component,
		[FiberTag.ROOT] = Reconciler.update_root_component,
		[FiberTag.TEXT] = Reconciler.update_text_component,

		["default"] = function()
			error(("Invalid Fiber tag: %s"):format(wip.tag))
		end,
	})

	return next_work(self, current, wip)
end

---@param fiber markup.Fiber
function Reconciler:complete_work(fiber)
	if not FiberFlag.check(fiber, FiberFlag.PLACEMENT) then
		return
	end

	if fiber.state_node and fiber.tag ~= FiberTag.ROOT then
		local parent = fiber["return"]

		while parent and not parent["state_node"] do
			parent = parent["return"]
		end

		-- fiber root is an element node,
		-- so there should always be at least one parent
		assert(parent, "Parent node must exist, this is a bug.")
		parent.state_node:prepend_child(fiber.state_node)
	end
end

---@param current markup.Fiber?
function Reconciler:has_scheduled_update(current)
	return current and #current.update_queue > 0
end

---@param fiber markup.Fiber
function Reconciler:bailout(fiber)
	fiber.flags = FiberFlag.NONE
	self:clone_child_fibers(fiber)
	return fiber.child
end

---@param current? markup.Fiber
---@param wip markup.Fiber
function Reconciler:update_function_component(current, wip)
	local next_children = self:render_with_hooks(current, wip)

	Reconciler.static.wip_hook = nil
	if current and FiberFlag.check(wip, FiberFlag.UPDATE) then
		-- bailoutHooks(current, workInProgress, renderLanes);
		-- return bailoutOnAlreadyFinishedWork(current, workInProgress, renderLanes);
	end

	wip.child = self:reconcile_children(current, wip, next_children)
	return wip.child
end

function Reconciler:update_fragment_component(current, wip)
	return nil
end

---@param current? markup.Fiber
---@param wip markup.Fiber
function Reconciler:update_root_component(current, wip)
	assert(current, "Root must have a current fiber, this is a bug.")

	-- local prev_state = current.memoized_state
	-- local next_props = wip.pending_props
	-- local next_state = wip.memoized_state

	wip.child = self:reconcile_children(current, wip, wip.pending_props.children)
	return wip.child
end

---@param current? markup.Fiber
---@param wip markup.Fiber
function Reconciler:update_text_component(current, wip)
	if not current then
		-- If there is no current fiber, create a new one
		wip.state_node = wip.type(wip.pending_props)
	else
		if vim.deep_equal(current.memoized_props, wip.pending_props) then
			-- Reuse the current fiber if the props are the same
			wip = current
		else
			-- Reuse the current fiber with new props
			wip = self:use_fiber(current, wip.pending_props)
		end
	end
end

---@param current? markup.Fiber
---@param wip markup.Fiber
function Reconciler:update_element_component(current, wip)
	-- local prev_props = current and current.memoized_props
	local next_props = wip.pending_props
	local next_children = next_props.children
	local prev_props = current and current.memoized_props

	-- local is_direct_text_child = type(next_children) == "string" or type(next_children) == "number"
	-- if is_direct_text_child then
	-- 	next_children = nil
	-- end
	-- log.info("123")

	wip.child = self:reconcile_children(current, wip, next_children)
	return wip.child
end

---@param current? markup.Fiber
---@param wip markup.Fiber
function Reconciler:render_with_hooks(current, wip)
	local Component = wip.type
	local props = wip.pending_props

	-- wip.memoized_state = nil
	-- if current and current.memoized_state then
	-- 	wip.memoized_state = current.memoized_state
	-- end

	local children = Component(props)

	return children
end

function Reconciler:delete_child(returnf, child)
	--
end

---@param returnf markup.Fiber
---@param child markup.xElement
function Reconciler:create_child(returnf, child)
	if (type(child) == "string" and child ~= "") or type(child) == "number" then
		local fiber = markup.create_fiber_from_text(child)
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

	while current_child and current_child.sibling do
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
	wip.child = current.child
	wip.memoized_state = current.memoized_state
	wip.memoized_props = current.memoized_props
	wip.update_queue = current.update_queue
	wip.flags = FiberFlag.NONE

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
		return Reconciler:update_text_node(returnf, matched, new_child)
	end

	if new_child.type then
		local matched = existing[new_child.key or new_index]
		return Reconciler:update_element_node(returnf, matched, new_child)
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

---@param returnf markup.Fiber
---@param current? markup.Fiber
---@param element markup.xElement
function Reconciler:update_element_node(returnf, current, element)
	if current and current.type ~= element.type then
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
	local new_index = 1
	local last_placed_index = 1

	local old_fiber = current_first_child
	local next_old_fiber = nil
	local prev_new_fiber = nil
	local result_first_child = nil

	while old_fiber and new_index <= #new_children do
		last_placed_index = self:place_child(old_fiber, last_placed_index, new_index)
		old_fiber = old_fiber.sibling

		new_index = new_index + 1
	end

	if new_index == #new_children + 1 then
		self:delete_remaining_children(returnf, old_fiber)
		return result_first_child
	end

	if not old_fiber then
		while new_index <= #new_children do
			local new_fiber = self:create_child(returnf, new_children[new_index])

			if new_fiber then
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
	return Reconciler:reconcile_child_fibers(wip, (current or {}).child, next_children)
end

---@param returnf markup.Fiber
---@param current_first_child? markup.Fiber
---@param new_child markup.xElement
function Reconciler:reconcile_child_fibers(returnf, current_first_child, new_child)
	if (type(new_child) == "string" and new_child ~= "") or type(new_child) == "number" then
		return Reconciler:reconcile_single_text(returnf, current_first_child, new_child)
	end

	if vim.islist(new_child) then
		return self:reconcile_children_list(returnf, current_first_child, new_child)
	elseif type(new_child) == "table" then
		return self:reconcile_single_element(returnf, current_first_child, new_child)
	end

	-- return Fiber.delete_remaining_children(returnf, current_first_child)
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

---@param new_fiber? markup.Fiber
---@param last_placed_index integer
---@param new_index integer
function Reconciler:place_child(new_fiber, last_placed_index, new_index)
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
function Reconciler:reconcile_single_element(returnf, current_first_child, element)
	local key = element.key
	local child = current_first_child

	-- iterate over existing children
	-- while child do
	-- 	if child.key == key then
	-- 		-- if the key matches, update the existing child
	-- 		-- return Reconciler:update_element_node(returnf, child, element)
	-- 	else
	-- 		self:delete_child(returnf, child)
	-- 	end
	--
	-- 	child = child.sibling
	-- end

	local created = markup.create_fiber_from_element(element)
	created["return"] = returnf
	return created
end

---@param fiber markup.Fiber
---@param props any
function Reconciler:use_fiber(fiber, props)
	local clone = markup.create_fiber(fiber.type, props, fiber.key)
	clone.tag = fiber.tag
	clone.state_node = fiber.state_node
	clone.alternate = fiber
	fiber.alternate = clone
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
		return fiber
	end
end

function Reconciler:mount_wip_hook()
	---@type markup.Fiber.hook
	local hook = {
		memoized_state = nil,
		base_state = nil,
		base_queue = nil,
		queue = nil,
		next = nil,
	}

	if not self.wip_hook then
		-- first hook to be mounted
		self.wip_hook = hook
		self.currently_rendering_fiber.memoized_state = hook
	else
		self.wip_hook.next = hook
		self.wip_hook = hook
	end

	return self.wip_hook
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

function Reconciler:print()
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

	print_fiber_tree(self.renderer.root.current, 0)
	log.info(table.concat(lines, "\n"))
end

---@alias markup.Reconciler.constructor
---| fun(renderer: markup.Renderer): markup.Reconciler
---| { static: markup.Reconciler.static }
---| markup.Reconciler.static

---@type markup.Reconciler.constructor
return Reconciler
