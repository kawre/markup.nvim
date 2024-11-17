local markup = require("markup")
local log = require("markup.logger") ---@diagnostic disable-line: unused-local

---@class markup.Pre : markup.Block
---@field protected super markup.Block
local Pre = markup.Block:extend("markup.block.pre") ---@diagnostic disable-line: undefined-field

function Pre:after_render()
	-- for _, child in ipairs(self.children) do
	-- 	local lines = child:computed_lines()
	-- 	child:_reset_lines()
	--
	-- 	for row, line in pairs(lines) do
	-- 		for _, text in ipairs(line:texts()) do
	-- 			for i, part in ipairs(text:split_at_newl()) do
	-- 				child:_line(row + (i - 1)):append(part)
	-- 			end
	-- 		end
	-- 	end
	-- end

	Pre.super.after_render(self)
end

---@alias markup.Pre.constructor markup.Block.constructor

---@type markup.Pre.constructor
return Pre
