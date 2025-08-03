local Impl = require("markup.renderer.box.impl")
local RenderBlock = require("markup.renderer.box.impl.block")
local RenderInblock = require("markup.renderer.box.impl.inblock")

---@class markup.box.inline : markup.box.impl
local M = Impl("RenderInline", { "inline" })

---@alias markup.layout.lines { lines: string[][], width: number, height: number }

---@param box markup.box
---@param input markup.box.layout.Input
function M.layout(box, input)
	local props = box.props
	local output = M.compute_output(box, input)
	local available_width = output.available_width

	local lines, w, h = {}, 0, 1

	local len = box:children_len()
	for i, child in box:iter_children() do
		if child:is("block") then
			error("Inline box cannot contain block elements")
		end

		local out = child:layout(output) ---@type markup.layout.lines
		for _, line in ipairs(out.lines) do
			for _, word in ipairs(line) do
				local taken = vim.fn.strcharlen(word) + (i ~= len and props.spacing or 0)
				if box.x + taken > available_width then
					h = h + 1
					box.x = 0
				end
				box.x = box.x + taken --FIX remove gap
				w = math.max(w, box.x)

				if not lines[h] then
					lines[h] = {}
				end
				table.insert(lines[h], word)
			end
		end

		-- local mbox = child:get_box_size("margin")

		-- local taken = mbox.width + (i ~= len and props.spacing or 0)
		-- if box.x + taken > available_width then
		-- 	-- If the next child does not fit, we need to wrap to the next line
		-- 	box.x = 0
		-- 	box.y = box.y + 1
		--
		-- 	child:layout(output)
		-- 	mbox = child:get_box_size("margin")
		-- else
		-- 	box.x = box.x + taken
		-- end
	end

	box.width = w
	box.height = box.y + 1

	box:set_content_box_width(box.width, true)
	box:set_content_box_height(box.height, true)
	-- RenderBlock.compute_final_size(box, input, output)

	return { lines = lines, width = box.width, height = box.height }
end

---@param box markup.box
---@param input markup.box.layout.Input
function M.compute_output(box, input)
	local width = box:resolve_size(box.computed.width, input.available_width)
	return { available_width = box:clamp_size(width, "width") }
end

return M
