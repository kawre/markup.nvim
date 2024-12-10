local log = require("markup.logger") ---@diagnostic disable-line: unused-local
local FiberTag = require("markup.core.reconciler.enum").Tag
local FiberFlag = require("markup.core.reconciler.enum").Flag
local markup = require("markup.core")

---@class markup.Reconciler : markup.Object
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

---@param renderer markup.Renderer
function Reconciler:init(renderer)
	self.currently_rendering_fiber = nil
	self.update_queue = markup.Array()
	self.work_stack = markup.Array()
	self.renderer = renderer
end

---@return markup.Fiber
function Reconciler:reconcile()
	Reconciler.static.currently_working_reconciler = self
	self:work_loop()
	Reconciler.static.currently_working_reconciler = nil

	return self.renderer.root.current
end

function Reconciler:work_loop()
	self.work_stack:push(self.renderer.root.current)
	self.work_stack_visited = {}

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
		return
	end

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
	if current then
		local old_props, new_props = current.memoized_props, wip.pending_props
		if vim.deep_equal(old_props, new_props) and current.type == wip.type then
			-- If the props and type are the same,
			-- we can reuse the current fiber
			wip.flag = nil
			return wip.child
		else
			wip.flag = FiberFlag.UPDATE
		end
	else
		wip.flag = FiberFlag.PLACEMENT
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
	local parent = fiber["return"]

	while parent and not parent["state_node"] do
		parent = parent["return"]
	end

	if parent then
		if fiber.tag == FiberTag.ELEMENT or fiber.tag == FiberTag.TEXT then
			fiber.state_node = fiber.type(fiber.pending_props)
			parent.state_node:append_child(fiber.state_node)
		end
	end
end

---@param current? markup.Fiber
---@param wip markup.Fiber
function Reconciler:update_function_component(current, wip)
	local next_children = self:render_with_hooks(current, wip)

	if current and wip.flag == FiberFlag.UPDATE then
		-- bailoutHooks(current, workInProgress, renderLanes);
		-- return bailoutOnAlreadyFinishedWork(current, workInProgress, renderLanes);
	end

	wip.child = self:reconcile_children(current, wip, next_children)
	return wip.child
end

function Reconciler:update_fragment_component(current, wip)
	return nil
end

function Reconciler:update_root_component(current, wip)
	assert(current, "Root must have a current fiber, this is a bug.")

	wip.child = self:reconcile_children(current, wip, wip.pending_props.children)
	return wip.child
end

function Reconciler:update_text_component()
	-- return nil
end

---@param current? markup.Fiber
---@param wip markup.Fiber
function Reconciler:update_element_component(current, wip)
	-- local prev_props = current and current.memoized_props
	local next_props = wip.pending_props
	local next_children = next_props.children

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
		last_placed_index = Reconciler:place_child(old_fiber, last_placed_index, new_index)
		old_fiber = old_fiber.sibling

		new_index = new_index + 1
	end

	if new_index == #new_children + 1 then
		Reconciler:delete_remaining_children(returnf, old_fiber)
		return result_first_child
	end

	if not old_fiber then
		while new_index <= #new_children do
			local new_fiber = Reconciler:create_child(returnf, new_children[new_index])

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

	local existing_children = Reconciler:map_remaining_children(returnf, old_fiber)

	while new_index <= #new_children do
		local new_fiber = Reconciler:update_from_map(
			existing_children,
			returnf,
			new_index,
			new_children[new_index]
		)

		if new_fiber then
			last_placed_index = Reconciler:place_child(new_fiber, last_placed_index, new_index)

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

	local created
	if element.type == FiberTag.FRAGMENT then
		created = markup.create_fiber_from_fragment(element.props.children)
	else
		created = markup.create_fiber_from_element(element)
	end

	created["return"] = returnf
	return created
end

function Reconciler:use_fiber(fiber, props)
	local clone = markup.create_fiber(fiber.type, props, fiber.key)
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
		current.pending_props = content
		return current
	end

	local fiber = markup.create_fiber_from_text(content)
	fiber["return"] = returnf
	return fiber
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
