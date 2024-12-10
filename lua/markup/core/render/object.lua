local markup = require("markup.core")

local log = require("markup.logger") ---@diagnostic disable-line: unused-local

---@class markup.Render.Object : markup.Object
---@field children markup.Render.Object[]
---@field node markup.Node
---@field builder markup.Renderer.Builder
local RenderObject = markup.Object("markup.render.object")

---@class markup.Render.Object.static : markup.Object.static
RenderObject.static = RenderObject.static

function RenderObject:first_child() end

function RenderObject:last_child() end

function RenderObject:prev_sibling() end

function RenderObject:next_sibling() end

function RenderObject:computed_lines()
	return self.builder.lines
end

return RenderObject
