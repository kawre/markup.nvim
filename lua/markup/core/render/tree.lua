local RenderNodeFactory = require("markup.core.factory.render-box")
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
	local mbox = self.root:margin_box_size()

	local lines = {}
	local fill = (" "):rep(1000)
	for i = 1, math.max(mbox.height, 1000) do
		lines[i] = fill
	end
	vim.api.nvim_buf_set_lines(self.renderer.bufnr, 0, -1, false, lines)

	self:traverse_and_paint(0, 0, self.root)
end

---(x, y) are the coordinates of the parent margin box
---@param x integer
---@param y integer
---@param box markup.Render.Box
function RenderTree:traverse_and_paint(x, y, box)
	if box:is("text") then
		box:paint(self.renderer, x, y)
		return
	end

	local props = box.props
	local cox = x + props.margin_left + props.padding_left
	local coy = y + props.margin_top + props.padding_top

	for _, child in box:iter_children() do
		local nx = cox + child.ox
		local ny = coy + child.oy
		self:traverse_and_paint(nx, ny, child)
	end

	if props.style.bg then
		box:paint(self.renderer, cox, coy)
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

	---@param box markup.Render.Box
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
