local RenderNodeFactory = require("markup.core.factory.render-node")
local log = require("markup.logger") ---@diagnostic disable-line: unused-local

---@class markup.Render.Tree
local RenderTree = {}
RenderTree.__index = RenderTree

---@param renderer markup.Renderer
function RenderTree:new(renderer)
	self = setmetatable({}, RenderTree)

	self.renderer = renderer
	self.root = RenderNodeFactory.create_root(renderer)

	return self
end

function RenderTree:build()
	self.root:build()
end

function RenderTree:layout()
	-- self.root:layout()
	for _, child in ipairs(self.root.children) do
		child:layout()
	end
end

function RenderTree:paint()
	local width = self.root.available_width
	local height = self.root.available_height

	local lines = {}
	local fill = (" "):rep(1000)
	for i = 1, math.max(height, 1000) do
		lines[i] = fill
	end
	vim.api.nvim_buf_set_lines(self.renderer.bufnr, 0, -1, false, lines)

	self:traverse_and_paint(0, 0, self.root)
end

---@param x integer
---@param y integer
---@param box markup.Render.Node
function RenderTree:traverse_and_paint(x, y, box)
	if box:is("text") then
		self:_paint_extmarks(x, y, box)
		return
	end

	for _, child in ipairs(box.children) do
		local props = child.props
		local new_x = x + props.margin_left + props.padding_left + child.ox
		local new_y = y + props.margin_top + props.padding_top + child.oy
		self:traverse_and_paint(new_x, new_y, child)
	end

	if box.props.style.bg then
		-- local hl = "MarkupDynamic" .. box.__id
		-- vim.api.nvim_set_hl(self.renderer.ns, hl, box.props.style)
		vim.api.nvim_buf_set_extmark(self.renderer.bufnr, self.renderer.ns, y, x, {
			end_line = y + box.height - 1,
			end_col = x + box.width,
			-- hl_mode = "blend",
			hl_group = box.props.style.bg,
			hl_mode = "combine",
		})
	end
end

function RenderTree:_paint_extmarks(x, y, box)
	local word = tostring(box.node.text_content)

	vim.api.nvim_buf_set_text(self.renderer.bufnr, y, x, y, x + #word, { word })
	-- local extmark_id = vim.api.nvim_buf_set_extmark(self.renderer.bufnr, self.renderer.ns, y, x, {
	-- 	virt_text = { { word } },
	-- 	virt_text_pos = "overlay",
	-- })

	-- table.insert(box.extmarks, extmark_id)
end

function RenderTree:_paint_grid()
	local width = self.root.width
	local height = self.root.height

	local grid = {}
	-- fill grid with spaces
	local empty = " "
	for y = 1, height do
		grid[y] = {}
		for x = 1, width do
			grid[y][x] = empty
		end
	end

	---@param box markup.Render.Node
	for _, box in ipairs(_MTEMP) do
		local x, y, word = box.x + 1, box.y + 1, tostring(box.node.text_content)
		for i = 1, #word do
			if not grid[y] then
				grid[y] = {}
				for k = 1, width do
					grid[y][k] = empty
				end
			end
			grid[y][x + i - 1] = word:sub(i, i)
		end
	end

	local lines = {}
	for y = 1, height do
		lines[y] = table.concat(grid[y])
	end

	vim.api.nvim_buf_set_lines(self.bufnr, 0, -1, false, lines)

	self.render_tree:layout()
	self.render_tree.view:layout()
	log.info(self.root)
	self.root.current.state_node:print()
	self:commit()
end

return RenderTree
