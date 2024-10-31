local markup = require("markup")
local utils = require("markup.utils")
local log = require("markup.logger")

---@alias markup.Box.align "start"|"center"|"end"
---@alias markup.Box.direction "row"|"column"

---@class markup.Box.props : markup.Element.props
---@field align markup.Box.align
---@field spacing integer
---@field direction markup.Box.direction

---@class markup.Box : markup.Element
---@field _ markup.Box.props
local Box = markup.Block:extend("MarkupBox")

---@param props markup.Box.constructor.props
function Box:init(props)
	props = vim.tbl_deep_extend("force", {
		align = "start",
		direction = "column",
		spacing = 0,
		children = {},
	}, props)

	Box.super.init(self, props)
end

-- function Box:content()
-- 	--    local children = self._.children
-- 	--    local content = {}
-- 	--
-- 	-- for _, elem in ipairs(children) do
-- 	--
-- 	-- end
--
-- 	return self._.children
-- end

---@param renderer markup.Renderer
---@param parent markup.Element
function Box:draw(renderer, parent)
	local content = self:content()

	local row, col = renderer:get_pos()
	if col ~= 0 then
		renderer:endl()
	end

	local window_width = vim.api.nvim_win_get_width(renderer._.winid)
	local xdd = renderer._.prev[row - 1] or 0

	for i, obj in ipairs(content) do
		-- log.debug({ prev_col = prev_col, prev_row = prev_row })
		local prev_row, prev_col = renderer:get_pos()
		obj:draw(renderer, self)
		local curr_row = self._.direction == "column" and renderer._.row - 1 or prev_row

		local lengths = {}
		for j = prev_row, curr_row do
			lengths[j] = renderer._.prev[j] - prev_col
		end

		-- log.debug(lengths)
		if #lengths > 1 then
			local largest_length = 0
			for _, value in pairs(lengths) do
				largest_length = math.max(value, largest_length)
			end
			for key, _ in pairs(lengths) do
				lengths[key] = largest_length
			end
		end
		-- log.debug(lengths)

		for r, l in pairs(lengths) do
			if self._.direction == "column" and self._.align ~= "start" then
				-- log.debug({ width = window_width, l = l, col = xdd })
				local pad = math.floor((window_width - l) / (self._.align == "center" and 2 or 1))
				renderer:pad_before(pad, r)
			end

			if self._.spacing > 0 then
				if self._.direction == "row" then
					renderer:pad(self._.spacing)
				else
					renderer:endl(self._.spacing)
				end
			end
		end
		vim.wait(250)
	end

	renderer:endl()
end

---@class markup.Box.constructor.props
---@field children markup.Element[]
---@field spacing? integer
---@field align? markup.Box.align
---@field direction? markup.Box.direction

---@alias markup.Box.constructor fun(props: markup.Element | markup.Box.constructor.props): markup.Box

---@type markup.Box.constructor
local MarkupBox = Box

return MarkupBox
